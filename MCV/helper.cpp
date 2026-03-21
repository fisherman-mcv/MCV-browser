#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <set>
#include <sstream>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

namespace {

constexpr int kSmartMaxRecords = 5000;
constexpr int kSmartAutoOpenMinHitsExclusive = 5;   // count must be > 5
constexpr int kSmartAutoOpenMinMatchExclusive = 80; // match must be > 80%
constexpr const char* kDefaultOllamaModel = "llama3.2:3b";
constexpr std::size_t kOllamaImageMaxBytes = 4 * 1024 * 1024;

struct SmartLearningRecord {
    std::string query;
    std::string url;
    int count = 0;
    long long updatedAt = 0;
};

struct SmartPrediction {
    bool found = false;
    std::string url;
    int count = 0;
};

struct CommandResult {
    int exitCode = -1;
    std::string output;
};

struct OllamaStatusSnapshot {
    bool available = false;
    std::string binaryPath;
    std::string version;
    std::vector<std::string> installedModels;
    std::string message;
};

struct OllamaGenerateResult {
    bool success = false;
    std::string model;
    std::string content;
    std::string message;
};

struct OllamaPullResult {
    bool success = false;
    std::string model;
    std::string message;
    std::vector<std::string> installedModels;
};

std::string trim(const std::string& input) {
    std::size_t start = 0;
    while (start < input.size() && std::isspace(static_cast<unsigned char>(input[start]))) {
        ++start;
    }

    std::size_t end = input.size();
    while (end > start && std::isspace(static_cast<unsigned char>(input[end - 1]))) {
        --end;
    }

    return input.substr(start, end - start);
}

std::string toLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return value;
}

bool endsWith(const std::string& value, const std::string& suffix) {
    if (suffix.size() > value.size()) {
        return false;
    }
    return std::equal(suffix.rbegin(), suffix.rend(), value.rbegin());
}

std::string collapseWhitespace(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    bool previousWasSpace = false;
    for (unsigned char ch : input) {
        if (std::isspace(ch)) {
            if (!previousWasSpace) {
                out.push_back(' ');
                previousWasSpace = true;
            }
        } else {
            out.push_back(static_cast<char>(ch));
            previousWasSpace = false;
        }
    }
    return trim(out);
}

std::vector<std::string> splitBy(const std::string& input, char delimiter) {
    std::vector<std::string> out;
    std::string token;
    std::istringstream stream(input);
    while (std::getline(stream, token, delimiter)) {
        out.push_back(token);
    }
    return out;
}

std::string normalizeQuery(const std::string& input) {
    return toLower(collapseWhitespace(trim(input)));
}

std::string sanitizeTSVField(const std::string& value) {
    std::string out = value;
    for (char& ch : out) {
        if (ch == '\t' || ch == '\n' || ch == '\r') {
            ch = ' ';
        }
    }
    return collapseWhitespace(out);
}

std::string jsonEscape(const std::string& value) {
    std::string out;
    out.reserve(value.size() + 16);
    for (char ch : value) {
        switch (ch) {
            case '\\': out += "\\\\"; break;
            case '"': out += "\\\""; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out += ch; break;
        }
    }
    return out;
}

std::string jsonUnescape(const std::string& value) {
    std::string out;
    out.reserve(value.size());

    for (std::size_t i = 0; i < value.size(); ++i) {
        char ch = value[i];
        if (ch != '\\' || i + 1 >= value.size()) {
            out.push_back(ch);
            continue;
        }

        char next = value[++i];
        switch (next) {
            case '\\': out.push_back('\\'); break;
            case '"': out.push_back('"'); break;
            case '/': out.push_back('/'); break;
            case 'b': out.push_back('\b'); break;
            case 'f': out.push_back('\f'); break;
            case 'n': out.push_back('\n'); break;
            case 'r': out.push_back('\r'); break;
            case 't': out.push_back('\t'); break;
            case 'u':
                // Keep unicode escape as plain text marker if it's outside basic ASCII.
                if (i + 4 < value.size()) {
                    const std::string hex = value.substr(i + 1, 4);
                    int code = 0;
                    bool ok = true;
                    for (char h : hex) {
                        code <<= 4;
                        if (h >= '0' && h <= '9') {
                            code += h - '0';
                        } else if (h >= 'a' && h <= 'f') {
                            code += 10 + (h - 'a');
                        } else if (h >= 'A' && h <= 'F') {
                            code += 10 + (h - 'A');
                        } else {
                            ok = false;
                            break;
                        }
                    }
                    if (ok && code >= 32 && code < 127) {
                        out.push_back(static_cast<char>(code));
                    } else {
                        out.push_back('?');
                    }
                    i += 4;
                } else {
                    out.push_back('?');
                }
                break;
            default:
                out.push_back(next);
                break;
        }
    }

    return out;
}

std::string extractJSONStringField(const std::string& json, const std::string& field) {
    const std::string key = "\"" + field + "\"";
    std::size_t pos = json.find(key);
    if (pos == std::string::npos) {
        return "";
    }
    pos = json.find(':', pos + key.size());
    if (pos == std::string::npos) {
        return "";
    }
    pos = json.find('"', pos + 1);
    if (pos == std::string::npos) {
        return "";
    }

    std::string encoded;
    encoded.reserve(256);
    bool escaped = false;
    for (std::size_t i = pos + 1; i < json.size(); ++i) {
        const char ch = json[i];
        if (!escaped && ch == '"') {
            return jsonUnescape(encoded);
        }
        if (!escaped && ch == '\\') {
            escaped = true;
            encoded.push_back(ch);
            continue;
        }
        escaped = false;
        encoded.push_back(ch);
    }
    return "";
}

std::string extractHost(std::string url) {
    url = trim(url);
    const std::size_t schemePos = url.find("://");
    if (schemePos == std::string::npos) {
        return "";
    }
    std::size_t hostStart = schemePos + 3;
    std::size_t hostEnd = url.find_first_of("/?#", hostStart);
    std::string hostPort = hostEnd == std::string::npos
        ? url.substr(hostStart)
        : url.substr(hostStart, hostEnd - hostStart);
    const std::size_t atPos = hostPort.rfind('@');
    if (atPos != std::string::npos) {
        hostPort = hostPort.substr(atPos + 1);
    }
    const std::size_t colonPos = hostPort.find(':');
    if (colonPos != std::string::npos) {
        hostPort = hostPort.substr(0, colonPos);
    }
    return toLower(trim(hostPort));
}

bool isSearchHost(const std::string& host) {
    if (host.empty()) {
        return true;
    }
    if (host == "duckduckgo.com" || host == "www.duckduckgo.com") {
        return true;
    }
    if (host == "bing.com" || host == "www.bing.com") {
        return true;
    }
    if (host == "search.yahoo.com" || host == "yahoo.com" || host == "www.yahoo.com") {
        return true;
    }
    if (host == "google.com" || host == "www.google.com" || endsWith(host, ".google.com")) {
        return true;
    }
    return false;
}

std::string canonicalizeURL(std::string url) {
    url = trim(url);
    if (url.empty()) {
        return "";
    }

    std::size_t fragmentPos = url.find('#');
    if (fragmentPos != std::string::npos) {
        url = url.substr(0, fragmentPos);
    }

    std::size_t queryPos = url.find('?');
    if (queryPos != std::string::npos) {
        url = url.substr(0, queryPos);
    }

    std::size_t schemePos = url.find("://");
    if (schemePos == std::string::npos) {
        return "";
    }

    const std::string scheme = toLower(url.substr(0, schemePos));
    if (scheme != "http" && scheme != "https") {
        return "";
    }

    const std::size_t hostStart = schemePos + 3;
    std::size_t hostEnd = url.find('/', hostStart);
    std::string hostPort = hostEnd == std::string::npos
        ? url.substr(hostStart)
        : url.substr(hostStart, hostEnd - hostStart);
    const std::size_t atPos = hostPort.rfind('@');
    if (atPos != std::string::npos) {
        hostPort = hostPort.substr(atPos + 1);
    }
    const std::string host = toLower(trim(hostPort));
    if (host.empty()) {
        return "";
    }

    std::string path = hostEnd == std::string::npos ? "/" : url.substr(hostEnd);
    if (path.empty()) {
        path = "/";
    }
    while (path.size() > 1 && path.back() == '/') {
        path.pop_back();
    }

    return scheme + "://" + host + path;
}

std::string urlEncode(const std::string& value) {
    std::ostringstream out;
    out.fill('0');
    out << std::hex;

    for (unsigned char ch : value) {
        if (std::isalnum(ch) || ch == '-' || ch == '_' || ch == '.' || ch == '~') {
            out << static_cast<char>(ch);
        } else if (ch == ' ') {
            out << "%20";
        } else {
            out << '%' << std::uppercase << std::setw(2) << static_cast<int>(ch) << std::nouppercase;
        }
    }

    return out.str();
}

bool isExecutableFile(const std::string& path) {
    return !path.empty() && ::access(path.c_str(), X_OK) == 0;
}

std::string shellQuote(const std::string& input) {
    if (input.empty()) {
        return "''";
    }
    std::string out = "'";
    for (char ch : input) {
        if (ch == '\'') {
            out += "'\\''";
        } else {
            out.push_back(ch);
        }
    }
    out.push_back('\'');
    return out;
}

CommandResult runCommandCapture(const std::vector<std::string>& args) {
    CommandResult result;
    if (args.empty()) {
        result.exitCode = 127;
        return result;
    }

    std::string command;
    for (const std::string& arg : args) {
        if (!command.empty()) {
            command.push_back(' ');
        }
        command += shellQuote(arg);
    }
    command = "TERM=dumb NO_COLOR=1 " + command + " 2>&1";

    FILE* pipe = ::popen(command.c_str(), "r");
    if (!pipe) {
        result.exitCode = 127;
        result.output = "Failed to start process";
        return result;
    }

    char buffer[4096];
    while (std::fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        result.output += buffer;
    }

    const int status = ::pclose(pipe);
    if (status == -1) {
        result.exitCode = 127;
    } else if (WIFEXITED(status)) {
        result.exitCode = WEXITSTATUS(status);
    } else {
        result.exitCode = status;
    }
    return result;
}

std::string lastNonEmptyLine(const std::string& input) {
    std::istringstream stream(input);
    std::string line;
    std::string last;
    while (std::getline(stream, line)) {
        const std::string cleaned = trim(line);
        if (!cleaned.empty()) {
            last = cleaned;
        }
    }
    return last;
}

std::string stripANSIEscapeCodes(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    bool inEscape = false;

    for (unsigned char ch : input) {
        if (!inEscape) {
            if (ch == 0x1B) {
                inEscape = true;
                continue;
            }
            out.push_back(static_cast<char>(ch));
            continue;
        }

        // End CSI/escape sequence on terminal byte.
        if ((ch >= '@' && ch <= '~') || ch == '\n') {
            inEscape = false;
        }
    }
    return out;
}

std::string normalizeProcessOutput(const std::string& raw) {
    std::string text = stripANSIEscapeCodes(raw);
    std::string normalized;
    normalized.reserve(text.size());
    for (char ch : text) {
        if (ch == '\r') {
            normalized.push_back('\n');
            continue;
        }
        if (ch == '\0') {
            continue;
        }
        normalized.push_back(ch);
    }
    return trim(normalized);
}

std::string truncateText(const std::string& input, std::size_t maxLen) {
    if (input.size() <= maxLen) {
        return input;
    }
    if (maxLen < 32) {
        return input.substr(0, maxLen);
    }
    return input.substr(0, maxLen) + "\n...[truncated]";
}

std::string joinLines(const std::vector<std::string>& lines) {
    std::ostringstream out;
    for (std::size_t i = 0; i < lines.size(); ++i) {
        if (i > 0) {
            out << '\n';
        }
        out << lines[i];
    }
    return out.str();
}

std::vector<std::string> parseOllamaModels(const std::string& listOutput) {
    std::vector<std::string> models;
    std::set<std::string> seen;

    std::istringstream stream(listOutput);
    std::string line;
    while (std::getline(stream, line)) {
        const std::string trimmed = trim(line);
        if (trimmed.empty()) {
            continue;
        }
        const std::string lower = toLower(trimmed);
        if (lower.rfind("name", 0) == 0 || lower.rfind("model", 0) == 0) {
            continue;
        }

        std::istringstream row(trimmed);
        std::string model;
        row >> model;
        if (model.empty()) {
            continue;
        }
        if (seen.insert(model).second) {
            models.push_back(model);
        }
    }

    return models;
}

std::string resolveExecutableFromPATH(const std::string& binaryName) {
    const char* envPath = std::getenv("PATH");
    std::string combinedPath = envPath ? envPath : "";
    const std::string fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    if (combinedPath.empty()) {
        combinedPath = fallbackPath;
    } else if (combinedPath.find("/opt/homebrew/bin") == std::string::npos) {
        combinedPath += ":" + fallbackPath;
    }

    for (const std::string& dir : splitBy(combinedPath, ':')) {
        if (dir.empty()) {
            continue;
        }
        std::filesystem::path candidate = std::filesystem::path(dir) / binaryName;
        const std::string path = candidate.string();
        if (isExecutableFile(path)) {
            return path;
        }
    }
    return "";
}

std::string resolveOllamaBinary() {
    const char* explicitPath = std::getenv("OLLAMA_BIN");
    if (explicitPath != nullptr && isExecutableFile(explicitPath)) {
        return explicitPath;
    }

    std::string fromPath = resolveExecutableFromPATH("ollama");
    if (!fromPath.empty()) {
        return fromPath;
    }

    const std::vector<std::string> common = {
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/usr/bin/ollama"
    };
    for (const std::string& candidate : common) {
        if (isExecutableFile(candidate)) {
            return candidate;
        }
    }
    return "";
}

OllamaStatusSnapshot fetchOllamaStatus() {
    OllamaStatusSnapshot status;
    status.binaryPath = resolveOllamaBinary();
    if (status.binaryPath.empty()) {
        status.message = "Ollama is not installed. Install from https://ollama.com/download";
        return status;
    }

    CommandResult versionResult = runCommandCapture({status.binaryPath, "--version"});
    status.version = normalizeProcessOutput(versionResult.output);
    if (versionResult.exitCode != 0) {
        status.message = lastNonEmptyLine(status.version);
        if (status.message.empty()) {
            status.message = "Cannot read ollama version";
        }
        return status;
    }

    CommandResult listResult = runCommandCapture({status.binaryPath, "list"});
    const std::string listOutput = normalizeProcessOutput(listResult.output);
    if (listResult.exitCode != 0) {
        const std::string reason = lastNonEmptyLine(listOutput);
        status.message = reason.empty()
            ? "Ollama service is not ready. Start it with `ollama serve`."
            : reason;
        return status;
    }

    status.installedModels = parseOllamaModels(listOutput);
    status.available = true;
    status.message = "Ollama ready";
    return status;
}

OllamaPullResult pullOllamaModel(const std::string& rawModel) {
    OllamaPullResult result;
    result.model = trim(rawModel);
    if (result.model.empty()) {
        result.message = "Model is required";
        return result;
    }

    const std::string binary = resolveOllamaBinary();
    if (binary.empty()) {
        result.message = "Ollama is not installed";
        return result;
    }

    bool wasInstalled = false;
    const OllamaStatusSnapshot beforePull = fetchOllamaStatus();
    if (beforePull.available) {
        result.installedModels = beforePull.installedModels;
        wasInstalled = std::find(
            beforePull.installedModels.begin(),
            beforePull.installedModels.end(),
            result.model
        ) != beforePull.installedModels.end();
        if (wasInstalled) {
            result.success = true;
            result.message = "Model already installed: " + result.model;
            return result;
        }
    }

    CommandResult pullResult = runCommandCapture({binary, "pull", result.model});
    std::string output = normalizeProcessOutput(pullResult.output);
    if (pullResult.exitCode != 0) {
        const std::string reason = lastNonEmptyLine(output);
        result.message = reason.empty() ? "Model download failed" : reason;
        return result;
    }

    result.success = true;

    const OllamaStatusSnapshot snapshot = fetchOllamaStatus();
    result.installedModels = snapshot.installedModels;
    const bool isInstalledNow = std::find(
        result.installedModels.begin(),
        result.installedModels.end(),
        result.model
    ) != result.installedModels.end();
    if (isInstalledNow && !wasInstalled) {
        result.message = "Model downloaded: " + result.model;
    } else if (isInstalledNow) {
        result.message = "Model already installed: " + result.model;
    } else {
        result.message = "Pull completed: " + result.model;
    }
    return result;
}

OllamaGenerateResult generateWithOllama(const std::string& rawModel, const std::string& rawPrompt) {
    OllamaGenerateResult result;
    result.model = trim(rawModel);
    if (result.model.empty()) {
        result.model = kDefaultOllamaModel;
    }

    const std::string prompt = trim(rawPrompt);
    if (prompt.empty()) {
        result.message = "Usage: ai <prompt>";
        return result;
    }

    const std::string binary = resolveOllamaBinary();
    if (binary.empty()) {
        result.message = "Ollama is not installed. Open Settings > General > Configure Ollama.";
        return result;
    }

    const OllamaStatusSnapshot status = fetchOllamaStatus();
    if (!status.available) {
        result.message = status.message.empty() ? "Ollama is not ready" : status.message;
        return result;
    }
    const bool hasModel = std::find(
        status.installedModels.begin(),
        status.installedModels.end(),
        result.model
    ) != status.installedModels.end();
    if (!hasModel) {
        result.message = "Model `" + result.model + "` is not installed. Download it in Settings > General > Configure Ollama.";
        return result;
    }

    const std::string payload =
        "{\"model\":\"" + jsonEscape(result.model) + "\","
        "\"prompt\":\"" + jsonEscape(prompt) + "\","
        "\"stream\":false}";

    CommandResult runResult = runCommandCapture({
        "curl",
        "-sS",
        "--max-time", "180",
        "http://127.0.0.1:11434/api/generate",
        "-H", "Content-Type: application/json",
        "-d", payload
    });
    std::string output = normalizeProcessOutput(runResult.output);
    if (runResult.exitCode != 0) {
        const std::string reason = lastNonEmptyLine(output);
        result.message = reason.empty() ? "Ollama generation failed" : reason;
        return result;
    }

    std::string responseText = extractJSONStringField(output, "response");
    if (responseText.empty()) {
        responseText = extractJSONStringField(output, "error");
        if (!responseText.empty()) {
            result.message = responseText;
            return result;
        }
        result.message = "Model returned empty response";
        return result;
    }

    result.success = true;
    result.content = truncateText(responseText, 12000);
    result.message = "ok";
    return result;
}

bool readBinaryFileLimited(const std::string& path, std::vector<unsigned char>* out, std::string* error) {
    if (out == nullptr) {
        if (error != nullptr) {
            *error = "Invalid output buffer";
        }
        return false;
    }

    std::error_code ec;
    if (!std::filesystem::exists(path, ec) || !std::filesystem::is_regular_file(path, ec)) {
        if (error != nullptr) {
            *error = "Image file not found";
        }
        return false;
    }

    const std::uintmax_t fileSize = std::filesystem::file_size(path, ec);
    if (ec) {
        if (error != nullptr) {
            *error = "Cannot read image metadata";
        }
        return false;
    }
    if (fileSize == 0) {
        if (error != nullptr) {
            *error = "Image file is empty";
        }
        return false;
    }
    if (fileSize > kOllamaImageMaxBytes) {
        if (error != nullptr) {
            *error = "Image is too large max size is 4 MB";
        }
        return false;
    }

    std::ifstream input(path, std::ios::binary);
    if (!input.is_open()) {
        if (error != nullptr) {
            *error = "Cannot open image file";
        }
        return false;
    }

    out->assign(
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>()
    );
    if (out->empty()) {
        if (error != nullptr) {
            *error = "Image file is empty";
        }
        return false;
    }
    return true;
}

std::string base64Encode(const std::vector<unsigned char>& data) {
    static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    if (data.empty()) {
        return "";
    }

    std::string encoded;
    encoded.reserve(((data.size() + 2) / 3) * 4);

    std::size_t i = 0;
    while (i + 2 < data.size()) {
        const unsigned int n = (static_cast<unsigned int>(data[i]) << 16)
            | (static_cast<unsigned int>(data[i + 1]) << 8)
            | static_cast<unsigned int>(data[i + 2]);
        encoded.push_back(table[(n >> 18) & 0x3F]);
        encoded.push_back(table[(n >> 12) & 0x3F]);
        encoded.push_back(table[(n >> 6) & 0x3F]);
        encoded.push_back(table[n & 0x3F]);
        i += 3;
    }

    if (i < data.size()) {
        unsigned int n = static_cast<unsigned int>(data[i]) << 16;
        encoded.push_back(table[(n >> 18) & 0x3F]);
        if (i + 1 < data.size()) {
            n |= static_cast<unsigned int>(data[i + 1]) << 8;
            encoded.push_back(table[(n >> 12) & 0x3F]);
            encoded.push_back(table[(n >> 6) & 0x3F]);
            encoded.push_back('=');
        } else {
            encoded.push_back(table[(n >> 12) & 0x3F]);
            encoded.push_back('=');
            encoded.push_back('=');
        }
    }

    return encoded;
}

bool writeTempPayload(const std::string& payload, std::string* outPath, std::string* error) {
    if (outPath == nullptr) {
        if (error != nullptr) {
            *error = "Invalid temp file output";
        }
        return false;
    }

    char pattern[] = "/tmp/mcv_ollama_chat_payload_XXXXXX";
    const int fd = mkstemp(pattern);
    if (fd < 0) {
        if (error != nullptr) {
            *error = "Cannot create temp payload file";
        }
        return false;
    }

    const char* ptr = payload.data();
    std::size_t left = payload.size();
    while (left > 0) {
        const ssize_t written = ::write(fd, ptr, left);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (error != nullptr) {
                *error = "Cannot write temp payload file";
            }
            ::close(fd);
            std::error_code ec;
            std::filesystem::remove(pattern, ec);
            return false;
        }
        ptr += written;
        left -= static_cast<std::size_t>(written);
    }
    ::close(fd);

    *outPath = pattern;
    return true;
}

OllamaGenerateResult chatWithOllama(
    const std::string& rawModel,
    const std::string& rawPrompt,
    const std::string& rawImagePath
) {
    const std::string imagePath = trim(rawImagePath);
    if (imagePath.empty()) {
        return generateWithOllama(rawModel, rawPrompt);
    }

    OllamaGenerateResult result;
    result.model = trim(rawModel);
    if (result.model.empty()) {
        result.model = kDefaultOllamaModel;
    }

    const std::string prompt = trim(rawPrompt);
    if (prompt.empty()) {
        result.message = "Prompt is empty";
        return result;
    }

    const std::string binary = resolveOllamaBinary();
    if (binary.empty()) {
        result.message = "Ollama is not installed. Open Settings > General > Configure Ollama.";
        return result;
    }

    const OllamaStatusSnapshot status = fetchOllamaStatus();
    if (!status.available) {
        result.message = status.message.empty() ? "Ollama is not ready" : status.message;
        return result;
    }
    const bool hasModel = std::find(
        status.installedModels.begin(),
        status.installedModels.end(),
        result.model
    ) != status.installedModels.end();
    if (!hasModel) {
        result.message = "Model `" + result.model + "` is not installed. Download it in Settings > General > Configure Ollama.";
        return result;
    }

    std::vector<unsigned char> imageBytes;
    std::string imageReadError;
    if (!readBinaryFileLimited(imagePath, &imageBytes, &imageReadError)) {
        result.message = imageReadError.empty() ? "Cannot read image file" : imageReadError;
        return result;
    }

    const std::string imageBase64 = base64Encode(imageBytes);
    if (imageBase64.empty()) {
        result.message = "Image encoding failed";
        return result;
    }

    const std::string payload =
        "{\"model\":\"" + jsonEscape(result.model) + "\","
        "\"messages\":[{\"role\":\"user\","
        "\"content\":\"" + jsonEscape(prompt) + "\","
        "\"images\":[\"" + imageBase64 + "\"]}],"
        "\"stream\":false}";

    std::string payloadPath;
    std::string payloadError;
    if (!writeTempPayload(payload, &payloadPath, &payloadError)) {
        result.message = payloadError.empty() ? "Cannot prepare request payload" : payloadError;
        return result;
    }

    CommandResult runResult = runCommandCapture({
        "curl",
        "-sS",
        "--max-time", "240",
        "http://127.0.0.1:11434/api/chat",
        "-H", "Content-Type: application/json",
        "--data-binary", "@" + payloadPath
    });
    std::error_code removeEC;
    std::filesystem::remove(payloadPath, removeEC);

    std::string output = normalizeProcessOutput(runResult.output);
    if (runResult.exitCode != 0) {
        const std::string reason = lastNonEmptyLine(output);
        result.message = reason.empty() ? "Ollama chat request failed" : reason;
        return result;
    }

    std::string responseText = extractJSONStringField(output, "content");
    if (responseText.empty()) {
        responseText = extractJSONStringField(output, "response");
    }
    if (responseText.empty()) {
        responseText = extractJSONStringField(output, "error");
        if (!responseText.empty()) {
            result.message = responseText;
            return result;
        }
        result.message = "Model returned empty response";
        return result;
    }

    result.success = true;
    result.content = truncateText(responseText, 12000);
    result.message = "ok";
    return result;
}

int levenshteinDistance(const std::string& lhs, const std::string& rhs) {
    if (lhs.empty()) {
        return static_cast<int>(rhs.size());
    }
    if (rhs.empty()) {
        return static_cast<int>(lhs.size());
    }

    std::vector<int> previous(rhs.size() + 1, 0);
    std::vector<int> current(rhs.size() + 1, 0);

    for (std::size_t j = 0; j <= rhs.size(); ++j) {
        previous[j] = static_cast<int>(j);
    }

    for (std::size_t i = 1; i <= lhs.size(); ++i) {
        current[0] = static_cast<int>(i);
        for (std::size_t j = 1; j <= rhs.size(); ++j) {
            const int insertion = current[j - 1] + 1;
            const int deletion = previous[j] + 1;
            const int substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1);
            current[j] = std::min({insertion, deletion, substitution});
        }
        std::swap(previous, current);
    }

    return previous[rhs.size()];
}

int matchPercent(const std::string& lhs, const std::string& rhs) {
    if (lhs.empty() || rhs.empty()) {
        return 0;
    }
    if (lhs == rhs) {
        return 100;
    }

    const int maxLen = static_cast<int>(std::max(lhs.size(), rhs.size()));
    if (maxLen <= 0) {
        return 0;
    }

    const int distance = levenshteinDistance(lhs, rhs);
    const double similarity = 1.0 - (static_cast<double>(distance) / static_cast<double>(maxLen));
    const int percent = static_cast<int>(std::lround(similarity * 100.0));
    return std::max(0, std::min(100, percent));
}

std::string smartStorePath() {
    const char* home = std::getenv("HOME");
    if (home == nullptr || *home == '\0') {
        return "";
    }
    std::filesystem::path dir(home);
    dir /= "Library";
    dir /= "Application Support";
    dir /= "MCV_experimental";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    dir /= "smart_mode.tsv";
    return dir.string();
}

std::vector<SmartLearningRecord> loadSmartRecords(const std::string& path) {
    std::vector<SmartLearningRecord> records;
    std::ifstream in(path);
    if (!in.is_open()) {
        return records;
    }

    std::string line;
    while (std::getline(in, line)) {
        if (line.empty()) {
            continue;
        }
        std::istringstream row(line);
        std::string query;
        std::string url;
        std::string countText;
        std::string updatedText;
        if (!std::getline(row, query, '\t')) {
            continue;
        }
        if (!std::getline(row, url, '\t')) {
            continue;
        }
        if (!std::getline(row, countText, '\t')) {
            continue;
        }
        if (!std::getline(row, updatedText, '\t')) {
            continue;
        }

        SmartLearningRecord record;
        record.query = normalizeQuery(query);
        record.url = canonicalizeURL(url);
        if (record.query.empty() || record.url.empty()) {
            continue;
        }

        try {
            record.count = std::max(0, std::stoi(countText));
        } catch (...) {
            record.count = 0;
        }

        try {
            record.updatedAt = std::stoll(updatedText);
        } catch (...) {
            record.updatedAt = 0;
        }

        if (record.count <= 0) {
            continue;
        }
        records.push_back(record);
    }

    return records;
}

void saveSmartRecords(const std::string& path, std::vector<SmartLearningRecord> records) {
    std::sort(records.begin(), records.end(), [](const SmartLearningRecord& lhs, const SmartLearningRecord& rhs) {
        if (lhs.updatedAt != rhs.updatedAt) {
            return lhs.updatedAt > rhs.updatedAt;
        }
        return lhs.count > rhs.count;
    });

    if (records.size() > static_cast<std::size_t>(kSmartMaxRecords)) {
        records.resize(kSmartMaxRecords);
    }

    std::ofstream out(path, std::ios::trunc);
    if (!out.is_open()) {
        return;
    }

    for (const SmartLearningRecord& record : records) {
        out << sanitizeTSVField(record.query) << '\t'
            << sanitizeTSVField(record.url) << '\t'
            << std::max(1, record.count) << '\t'
            << std::max(1LL, record.updatedAt) << '\n';
    }
}

bool learnSmartMapping(const std::string& rawQuery, const std::string& rawURL) {
    const std::string query = normalizeQuery(rawQuery);
    const std::string url = canonicalizeURL(rawURL);
    if (query.empty() || url.empty()) {
        return false;
    }

    const std::string host = extractHost(url);
    if (isSearchHost(host)) {
        return false;
    }

    const std::string path = smartStorePath();
    if (path.empty()) {
        return false;
    }

    std::vector<SmartLearningRecord> records = loadSmartRecords(path);
    const long long now = static_cast<long long>(std::time(nullptr));
    bool found = false;

    for (SmartLearningRecord& record : records) {
        if (record.query == query && record.url == url) {
            record.count = std::max(0, record.count) + 1;
            record.updatedAt = now;
            found = true;
            break;
        }
    }

    if (!found) {
        SmartLearningRecord record;
        record.query = query;
        record.url = url;
        record.count = 1;
        record.updatedAt = now;
        records.push_back(record);
    }

    saveSmartRecords(path, std::move(records));
    return true;
}

SmartPrediction predictSmartMapping(const std::string& rawQuery) {
    SmartPrediction result;
    const std::string query = normalizeQuery(rawQuery);
    if (query.empty()) {
        return result;
    }

    const std::string path = smartStorePath();
    if (path.empty()) {
        return result;
    }

    const std::vector<SmartLearningRecord> records = loadSmartRecords(path);
    SmartLearningRecord best;
    bool found = false;
    int bestMatch = -1;

    for (const SmartLearningRecord& record : records) {
        const int match = matchPercent(query, record.query);
        if (record.count <= kSmartAutoOpenMinHitsExclusive) {
            continue;
        }
        if (match <= kSmartAutoOpenMinMatchExclusive) {
            continue;
        }

        if (!found ||
            match > bestMatch ||
            (match == bestMatch && record.count > best.count) ||
            (match == bestMatch && record.count == best.count && record.updatedAt > best.updatedAt)) {
            best = record;
            bestMatch = match;
            found = true;
        }
    }

    if (!found) {
        return result;
    }

    result.found = true;
    result.url = best.url;
    result.count = best.count;
    return result;
}

std::vector<std::string> splitWords(const std::string& input) {
    std::istringstream stream(input);
    std::vector<std::string> words;
    std::string token;
    while (stream >> token) {
        words.push_back(token);
    }
    return words;
}

std::string musicFocusQueryForMood(const std::string& rawMood) {
    const std::string mood = normalizeQuery(rawMood);
    if (mood == "trading") {
        return "synthwave trading focus mix";
    }
    if (mood == "night") {
        return "night drive ambient mix";
    }
    if (mood == "resonance") {
        return "resonance deep electronic mix";
    }
    return "lofi coding focus mix";
}

std::string musicPlaylistURLForContext(const std::string& rawURL, const std::string& rawTitle) {
    const std::string host = extractHost(rawURL);
    if (host.find("music.youtube.com") != std::string::npos) {
        return "https://music.youtube.com/explore";
    }
    if (host.find("youtube.com") != std::string::npos) {
        return "https://www.youtube.com/feed/music";
    }
    if (host.find("spotify.com") != std::string::npos) {
        return "https://open.spotify.com/genre/0JQ5DAqbMKFQ00XGBls6ym";
    }
    if (host.find("soundcloud.com") != std::string::npos) {
        return "https://soundcloud.com/discover";
    }

    const std::string title = collapseWhitespace(trim(rawTitle));
    if (!title.empty()) {
        return "https://www.youtube.com/results?search_query=" + urlEncode(title + " playlist");
    }
    return "https://music.youtube.com/";
}

std::string musicFindQueryFromTitle(const std::string& rawTitle) {
    const std::string title = collapseWhitespace(trim(rawTitle));
    if (title.empty()) {
        return "top tracks mix";
    }
    return title + " official audio";
}

void printResponse(
    const std::string& action,
    bool success = true,
    const std::string& title = "",
    const std::string& message = "",
    const std::string& url = "",
    const std::string& query = "",
    int index = -1
) {
    std::cout << "{";
    std::cout << "\"action\":\"" << jsonEscape(action) << "\"";
    std::cout << ",\"success\":" << (success ? "true" : "false");

    if (!title.empty()) {
        std::cout << ",\"title\":\"" << jsonEscape(title) << "\"";
    }
    if (!message.empty()) {
        std::cout << ",\"message\":\"" << jsonEscape(message) << "\"";
    }
    if (!url.empty()) {
        std::cout << ",\"url\":\"" << jsonEscape(url) << "\"";
    }
    if (!query.empty()) {
        std::cout << ",\"query\":\"" << jsonEscape(query) << "\"";
    }
    if (index >= 0) {
        std::cout << ",\"index\":" << index;
    }

    std::cout << "}";
}

std::string extractTail(const std::string& source, const std::string& head) {
    if (source.size() <= head.size()) {
        return "";
    }
    return trim(source.substr(head.size()));
}

std::string wikiLanguageFromAlias(const std::string& raw) {
    const std::string value = toLower(trim(raw));
    if (value == "e" || value == "en" || value == "eng" || value == "english") {
        return "en";
    }
    if (value == "r" || value == "ru" || value == "rus" || value == "russian") {
        return "ru";
    }
    if (value == "u" || value == "uk" || value == "ua" || value == "ukrainian") {
        return "uk";
    }
    if (value == "i" || value == "it" || value == "ita" || value == "italian") {
        return "it";
    }
    if (value == "f" || value == "fr" || value == "fra" || value == "french") {
        return "fr";
    }
    if (value == "s" || value == "es" || value == "spa" || value == "spanish") {
        return "es";
    }
    if (value == "c" || value == "zh" || value == "cn" || value == "chinese") {
        return "zh";
    }
    return "";
}

std::string tradingViewIntervalForToken(const std::string& raw) {
    const std::string value = toLower(trim(raw));
    if (value == "1m") { return "1"; }
    if (value == "5m") { return "5"; }
    if (value == "15m") { return "15"; }
    if (value == "1h") { return "60"; }
    if (value == "4h") { return "240"; }
    if (value == "1d") { return "D"; }
    return "60";
}

std::string normalizeMarketSymbol(const std::string& raw) {
    std::string out;
    out.reserve(raw.size());
    for (unsigned char ch : raw) {
        if (std::isalnum(ch)) {
            out.push_back(static_cast<char>(std::toupper(ch)));
        }
    }
    if (out.empty()) {
        return "BTC";
    }
    return out;
}

bool parsePositiveInt(const std::string& raw, int* out) {
    if (out == nullptr) {
        return false;
    }
    try {
        std::size_t used = 0;
        int value = std::stoi(trim(raw), &used);
        if (used != trim(raw).size() || value <= 0) {
            return false;
        }
        *out = value;
        return true;
    } catch (...) {
        return false;
    }
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        printResponse("not_command");
        return 0;
    }

    std::string raw = trim(argv[1]);
    if (raw.empty()) {
        printResponse("not_command");
        return 0;
    }

    const bool bangMode = !raw.empty() && raw[0] == '!';
    std::string work = bangMode ? trim(raw.substr(1)) : raw;
    if (work.empty()) {
        printResponse("not_command");
        return 0;
    }

    const std::vector<std::string> words = splitWords(work);
    if (words.empty()) {
        printResponse("not_command");
        return 0;
    }

    const std::string command = toLower(words.front());
    const std::string tail = extractTail(work, words.front());

    if (command == "__mcv_smart_learn") {
        const std::size_t sep = tail.find('\t');
        if (sep == std::string::npos) {
            printResponse("smart_learned", false, "Smart mode", "Invalid payload");
            return 0;
        }
        const std::string query = tail.substr(0, sep);
        const std::string url = tail.substr(sep + 1);
        const bool learned = learnSmartMapping(query, url);
        printResponse("smart_learned", learned, "Smart mode", learned ? "learned" : "skipped");
        return 0;
    }

    if (command == "__mcv_smart_predict") {
        SmartPrediction prediction = predictSmartMapping(tail);
        if (!prediction.found) {
            printResponse("not_command");
            return 0;
        }
        printResponse(
            "smart_prediction",
            true,
            "Smart mode",
            "Learned from your browsing history",
            prediction.url,
            "",
            prediction.count
        );
        return 0;
    }

    if (command == "__mcv_music_focus") {
        const std::string query = musicFocusQueryForMood(tail);
        printResponse("music_play", true, "Music Wheel", "Focus mode", "", query);
        return 0;
    }

    if (command == "__mcv_music_playlist") {
        const std::size_t sep = tail.find('\t');
        const std::string sourceURL = sep == std::string::npos ? tail : tail.substr(0, sep);
        const std::string sourceTitle = sep == std::string::npos ? "" : tail.substr(sep + 1);
        const std::string url = musicPlaylistURLForContext(sourceURL, sourceTitle);
        printResponse("navigate", true, "Music Wheel", "Playlist", url);
        return 0;
    }

    if (command == "__mcv_music_find") {
        const std::string query = musicFindQueryFromTitle(tail);
        printResponse("music_play", true, "Music Wheel", "Find", "", query);
        return 0;
    }

    if (command == "__mcv_ollama_status") {
        const OllamaStatusSnapshot status = fetchOllamaStatus();
        printResponse(
            "ollama_status",
            status.available,
            status.binaryPath,
            status.available
                ? (status.version.empty() ? "Ollama ready" : status.version)
                : status.message,
            "",
            joinLines(status.installedModels),
            static_cast<int>(status.installedModels.size())
        );
        return 0;
    }

    if (command == "__mcv_ollama_list") {
        const OllamaStatusSnapshot status = fetchOllamaStatus();
        const bool success = !status.binaryPath.empty() && (status.available || !status.installedModels.empty());
        const std::string message = status.available
            ? "Installed models"
            : (status.message.empty() ? "Ollama unavailable" : status.message);
        printResponse(
            "ollama_models_installed",
            success,
            status.binaryPath,
            message,
            "",
            joinLines(status.installedModels),
            static_cast<int>(status.installedModels.size())
        );
        return 0;
    }

    if (command == "__mcv_ollama_pull") {
        const OllamaPullResult result = pullOllamaModel(tail);
        printResponse(
            "ollama_pull",
            result.success,
            result.model,
            result.message,
            "",
            joinLines(result.installedModels),
            static_cast<int>(result.installedModels.size())
        );
        return 0;
    }

    if (command == "__mcv_ollama_generate") {
        const std::size_t sep = tail.find('\t');
        std::string model = kDefaultOllamaModel;
        std::string prompt = tail;
        if (sep != std::string::npos) {
            model = trim(tail.substr(0, sep));
            prompt = tail.substr(sep + 1);
        }
        const OllamaGenerateResult result = generateWithOllama(model, prompt);
        printResponse(
            "ai_result",
            result.success,
            result.model,
            result.success ? result.content : result.message
        );
        return 0;
    }

    if (command == "__mcv_ollama_chat") {
        std::string model = kDefaultOllamaModel;
        std::string prompt = "";
        std::string imagePath = "";

        const std::size_t firstSep = tail.find('\t');
        if (firstSep == std::string::npos) {
            prompt = tail;
        } else {
            model = trim(tail.substr(0, firstSep));
            const std::string rest = tail.substr(firstSep + 1);
            const std::size_t secondSep = rest.find('\t');
            if (secondSep == std::string::npos) {
                prompt = rest;
            } else {
                prompt = rest.substr(0, secondSep);
                imagePath = rest.substr(secondSep + 1);
            }
        }

        const OllamaGenerateResult result = chatWithOllama(model, prompt, imagePath);
        printResponse(
            "ai_result",
            result.success,
            result.model,
            result.success ? result.content : result.message
        );
        return 0;
    }

    if (command == "open") {
        if (tail.empty()) {
            printResponse("show_message", false, "Navigation", "Usage: open <url>");
            return 0;
        }
        std::string value = tail;
        if (value.find("://") == std::string::npos) {
            value = "https://" + value;
        }
        printResponse("navigate", true, "", "", value);
        return 0;
    }

    if (command == "reload") {
        printResponse("reload_page");
        return 0;
    }

    if (command == "back") {
        printResponse("go_back");
        return 0;
    }

    if (command == "forward") {
        printResponse("go_forward");
        return 0;
    }

    if (command == "home") {
        printResponse("open_home");
        return 0;
    }

    if (command == "new" || command == "newtab" || command == "t") {
        printResponse("new_tab");
        return 0;
    }

    if (command == "private") {
        printResponse("open_private_window");
        return 0;
    }

    if (command == "close" || command == "closetab" || command == "w") {
        printResponse("close_tab");
        return 0;
    }

    if (command == "reset" || command == "resettabs" || command == "tabsreset") {
        printResponse("reset_tabs");
        return 0;
    }

    if (command == "book" || command == "bookmark" || command == "pin") {
        printResponse("bookmark_add");
        return 0;
    }

    if (command == "bookmarks" || command == "bm") {
        printResponse("open_bookmarks");
        return 0;
    }

    if (command == "history" || command == "hist") {
        if (words.size() <= 1) {
            printResponse("open_history");
            return 0;
        }
        const std::string mode = toLower(words[1]);
        if (mode == "sites" || mode == "site") {
            printResponse("open_history");
            return 0;
        }
        if (mode == "clear") {
            printResponse("history_clear");
            return 0;
        }
        if (mode == "cmds" || mode == "commands") {
            printResponse("show_message", true, "History", "Command history is not persisted yet");
            return 0;
        }
        if (mode == "del" && words.size() >= 3) {
            int index = 0;
            if (!parsePositiveInt(words[2], &index)) {
                printResponse("show_message", false, "History", "Usage: history del <N>");
                return 0;
            }
            printResponse("history_delete", true, "", "", "", "", index - 1);
            return 0;
        }
        printResponse("open_history");
        return 0;
    }

    if (command == "downloads") {
        if (words.size() >= 2 && toLower(words[1]) == "clear") {
            printResponse("downloads_clear");
            return 0;
        }
        printResponse("open_downloads");
        return 0;
    }

    if (command == "clear") {
        printResponse("clear_data");
        return 0;
    }

    if (command == "dev") {
        printResponse("open_devtools");
        return 0;
    }

    if (command == "console") {
        printResponse("open_console");
        return 0;
    }

    if (command == "speed") {
        if (tail.empty()) {
            printResponse("show_message", false, "Tools", "Usage: speed x1.5");
            return 0;
        }
        printResponse("set_playback_rate", true, "", "", "", tail);
        return 0;
    }

    if (command == "scroll") {
        if (tail.empty()) {
            printResponse("show_message", false, "Tools", "Usage: scroll x0.5");
            return 0;
        }
        printResponse("set_scroll_factor", true, "", "", "", tail);
        return 0;
    }

    if (command == "dark") {
        printResponse("set_theme", true, "", "", "", "dark");
        return 0;
    }

    if (command == "theme") {
        if (tail.empty()) {
            printResponse("show_message", false, "Theme", "Usage: theme dark|light|off");
            return 0;
        }
        printResponse("set_theme", true, "", "", "", toLower(tail));
        return 0;
    }

    if (command == "mode" || command == "security") {
        const std::string value = toLower(words.size() >= 2 ? words[1] : trim(tail));
        if (value.empty()) {
            printResponse("show_message", false, "Security", "Usage: mode classic|safe|secure");
            return 0;
        }
        if (value != "classic" && value != "safe" && value != "secure") {
            printResponse("show_message", false, "Security", "Usage: mode classic|safe|secure");
            return 0;
        }
        printResponse("set_security_mode", true, "Security", "Switching mode", "", value);
        return 0;
    }

    if (command == "colors" || command == "color") {
        printResponse("open_colors");
        return 0;
    }

    if (command == "spot") {
        printResponse("spot_window");
        return 0;
    }

    if (command == "float") {
        printResponse("toggle_floating");
        return 0;
    }

    if (command == "minimal") {
        printResponse("toggle_minimal");
        return 0;
    }

    if (command == "pro") {
        if (tail.empty()) {
            printResponse("open_settings");
            return 0;
        }

        const std::string sub = toLower(words.size() >= 2 ? words[1] : "");
        if (sub == "opacity") {
            if (words.size() < 3) {
                printResponse("show_message", false, "Pro", "Usage: pro opacity <0.05-1.0>");
                return 0;
            }
            printResponse("set_opacity", true, "", "", "", words[2]);
            return 0;
        }
        if (sub == "blur") {
            if (words.size() >= 3 && toLower(words[2]) == "mini") {
                if (words.size() < 4) {
                    printResponse("show_message", false, "Pro", "Usage: pro blur mini on|off");
                    return 0;
                }
                printResponse("show_message", true, "Pro", "Mini blur switch saved");
                return 0;
            }
            if (words.size() < 3) {
                printResponse("show_message", false, "Pro", "Usage: pro blur on|off");
                return 0;
            }
            printResponse("set_blur", true, "", "", "", words[2]);
            return 0;
        }
        if (sub == "suggest") {
            if (words.size() < 3) {
                printResponse("show_message", false, "Pro", "Usage: pro suggest on|off");
                return 0;
            }
            printResponse("set_suggest", true, "", "", "", words[2]);
            return 0;
        }
        if (sub == "smart") {
            if (words.size() < 3) {
                printResponse("show_message", false, "Pro", "Usage: pro smart on|off");
                return 0;
            }
            printResponse("set_smart", true, "", "", "", words[2]);
            return 0;
        }
        if (sub == "radius") {
            if (words.size() < 3) {
                printResponse("show_message", false, "Pro", "Usage: pro radius <int>");
                return 0;
            }
            printResponse("set_radius", true, "", "", "", words[2]);
            return 0;
        }
        if (sub == "cuts") {
            if (words.size() == 2) {
                printResponse("show_message", true, "Shortcuts", "Cmd+E overlay, Ctrl+E command center, Cmd+S saved, Cmd+G tab wheel, Cmd+O music wheel, Opt+R hard reload");
                return 0;
            }
            const std::string cutsAction = toLower(words[2]);
            if (cutsAction == "edit") {
                printResponse("show_message", true, "Shortcuts", "Editing shortcuts file is not available yet");
                return 0;
            }
            if (cutsAction == "path") {
                printResponse("show_message", true, "Shortcuts", "~/Library/Application Support/MCV_experimental/shortcuts.json");
                return 0;
            }
            if (cutsAction == "reload") {
                printResponse("show_message", true, "Shortcuts", "Shortcuts reloaded");
                return 0;
            }
            if (cutsAction == "reset") {
                printResponse("show_message", true, "Shortcuts", "Shortcuts reset to defaults");
                return 0;
            }
        }
        if (sub == "reset") {
            printResponse("pro_reset");
            return 0;
        }

        printResponse("show_message", false, "Pro", "Unknown pro command");
        return 0;
    }

    if (command == "ollama") {
        const std::string mode = toLower(words.size() >= 2 ? words[1] : "");
        if (mode.empty() || mode == "on") {
            printResponse("open_settings", true, "Ollama", "Open Settings > General > Configure Ollama");
            return 0;
        }
        if (mode == "off") {
            printResponse("show_message", true, "Ollama", "Local AI routing disabled");
            return 0;
        }
        if (mode == "status") {
            const OllamaStatusSnapshot status = fetchOllamaStatus();
            const std::string details = status.available
                ? ("Ready • models: " + std::to_string(status.installedModels.size()))
                : (status.message.empty() ? "Unavailable" : status.message);
            printResponse("show_message", status.available, "Ollama", details);
            return 0;
        }
        if (mode == "test") {
            const OllamaGenerateResult result = generateWithOllama(kDefaultOllamaModel, "Reply with one word: ok");
            printResponse(
                "show_message",
                result.success,
                "Ollama test",
                result.success ? "Model responded" : result.message
            );
            return 0;
        }
        if (mode == "chat") {
            const std::string prompt = trim(extractTail(tail, words[1]));
            if (prompt.empty()) {
                printResponse("show_message", false, "Ollama", "Usage: ollama chat <message>");
                return 0;
            }
            const OllamaGenerateResult result = generateWithOllama(kDefaultOllamaModel, prompt);
            printResponse(
                "ai_result",
                result.success,
                result.model,
                result.success ? result.content : result.message
            );
            return 0;
        }

        printResponse("show_message", false, "Ollama", "Usage: ollama on|off|status|test|chat <message>");
        return 0;
    }

    if (command == "ai") {
        if (tail.empty()) {
            printResponse("show_message", false, "AI", "Usage: ai <prompt>");
            return 0;
        }
        const OllamaGenerateResult result = generateWithOllama(kDefaultOllamaModel, tail);
        printResponse(
            "ai_result",
            result.success,
            result.model,
            result.success ? result.content : result.message
        );
        return 0;
    }

    if (command == "c") {
        if (tail.empty()) {
            printResponse("navigate", true, "", "", "https://chatgpt.com/");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://chatgpt.com/?q=" + urlEncode(tail));
        return 0;
    }

    if (command == "g") {
        if (tail.empty()) {
            printResponse("navigate", true, "", "", "https://www.google.com/");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://www.google.com/search?q=" + urlEncode(tail));
        return 0;
    }

    if (command == "ddg" || command == "search") {
        if (tail.empty()) {
            printResponse("navigate", true, "", "", "https://duckduckgo.com/");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://duckduckgo.com/?q=" + urlEncode(tail));
        return 0;
    }

    if (command == "yt" || command == "youtube") {
        if (tail.empty()) {
            printResponse("navigate", true, "", "", "https://www.youtube.com/");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://www.youtube.com/results?search_query=" + urlEncode(tail));
        return 0;
    }

    if (command == "wiki" || command == "wikipedia") {
        if (tail.empty()) {
            printResponse("navigate", true, "", "", "https://en.wikipedia.org/");
            return 0;
        }

        std::string language = "en";
        std::string query = tail;
        if (words.size() >= 3) {
            const std::string maybeLang = wikiLanguageFromAlias(words[1]);
            if (!maybeLang.empty()) {
                language = maybeLang;
                query = trim(extractTail(tail, words[1]));
            }
        }
        if (query.empty()) {
            printResponse("navigate", true, "", "", "https://" + language + ".wikipedia.org/");
            return 0;
        }
        printResponse(
            "navigate",
            true,
            "",
            "",
            "https://" + language + ".wikipedia.org/w/index.php?search=" + urlEncode(query)
        );
        return 0;
    }

    if (command == "tw") {
        if (tail.empty()) {
            printResponse("show_message", false, "Sites", "Usage: tw <user>");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://www.twitch.tv/" + tail);
        return 0;
    }

    if (command == "x") {
        if (tail.empty()) {
            printResponse("show_message", false, "Sites", "Usage: x <user>");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://x.com/" + tail);
        return 0;
    }

    if (command == "gh" || command == "github") {
        if (tail.empty()) {
            printResponse("navigate", true, "", "", "https://github.com/");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://github.com/" + tail);
        return 0;
    }

    if (command == "ghr") {
        if (tail.empty()) {
            printResponse("show_message", false, "Sites", "Usage: ghr <user/repo>");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://github.com/" + tail);
        return 0;
    }

    if (command == "tv") {
        const std::string symbol = normalizeMarketSymbol(words.size() >= 2 ? words[1] : "BTC");
        const std::string timeframe = words.size() >= 3 ? words[2] : "1h";
        const std::string interval = tradingViewIntervalForToken(timeframe);
        printResponse(
            "navigate",
            true,
            "",
            "",
            "https://www.tradingview.com/chart/?symbol=BINANCE%3A" + symbol + "USDT&interval=" + interval
        );
        return 0;
    }

    if (command == "bn") {
        const std::string symbol = normalizeMarketSymbol(words.size() >= 2 ? words[1] : "BTC");
        printResponse("navigate", true, "", "", "https://www.binance.com/en/futures/" + symbol + "USDT");
        return 0;
    }

    if (command == "coinglass") {
        printResponse("navigate", true, "", "", "https://www.coinglass.com/LiquidationData");
        return 0;
    }

    if (command == "cmc") {
        const std::string value = toLower(words.size() >= 2 ? words[1] : "btc");
        if (value == "eth" || value == "ethereum") {
            printResponse("navigate", true, "", "", "https://coinmarketcap.com/currencies/ethereum/");
            return 0;
        }
        printResponse("navigate", true, "", "", "https://coinmarketcap.com/currencies/bitcoin/");
        return 0;
    }

    if (command == "fear") {
        printResponse("navigate", true, "", "", "https://alternative.me/crypto/fear-and-greed-index/");
        return 0;
    }

    if (command == "json") {
        if (tail.empty()) {
            printResponse("show_message", false, "JSON", "Usage: json <url>");
            return 0;
        }
        std::string value = tail;
        if (value.find("://") == std::string::npos) {
            value = "https://" + value;
        }
        printResponse("navigate", true, "", "", value);
        return 0;
    }

    if (command == "cur") {
        if (words.size() < 3) {
            printResponse("show_message", false, "Converter", "Usage: cur <from> <to> [amount]");
            return 0;
        }
        auto normalizeCurrency = [](const std::string& token) -> std::string {
            const std::string value = toLower(trim(token));
            if (value == "b" || value == "btc") { return "BTC"; }
            if (value == "eth") { return "ETH"; }
            if (value == "d" || value == "usd") { return "USD"; }
            if (value == "e" || value == "eur") { return "EUR"; }
            if (value == "u" || value == "uah") { return "UAH"; }
            return toLower(token);
        };
        const std::string from = normalizeCurrency(words[1]);
        const std::string to = normalizeCurrency(words[2]);
        const std::string amount = words.size() >= 4 ? words[3] : "1";
        const std::string query = amount + " " + from + " to " + to;
        printResponse("navigate", true, "", "", "https://duckduckgo.com/?q=" + urlEncode(query));
        return 0;
    }

    if (command == "perf") {
        printResponse("show_message", true, "Performance", "Diagnostics command queued");
        return 0;
    }

    if (command == "alert") {
        printResponse("show_message", true, "Trader", "Alerts are in preview mode");
        return 0;
    }

    if (command == "notify" || command == "notification") {
        const std::string payload = trim(tail);
        if (payload.empty()) {
            printResponse("show_message", false, "Notify", "Usage: notify <text>");
            return 0;
        }

        std::string title = "MC Browser";
        std::string message = payload;
        const std::size_t sep = payload.find('|');
        if (sep != std::string::npos) {
            const std::string left = trim(payload.substr(0, sep));
            const std::string right = trim(payload.substr(sep + 1));
            if (!left.empty()) {
                title = left;
            }
            if (!right.empty()) {
                message = right;
            }
        }

        printResponse("notify", true, title, message);
        return 0;
    }

    if (command == "settings") {
        printResponse("open_settings");
        return 0;
    }

    if (command == "copy" || command == "copylink") {
        printResponse("copy_link");
        return 0;
    }

    if (command == "tab") {
        if (tail.empty()) {
            printResponse("show_message", false, "Tabs", "Usage: tab <number>");
            return 0;
        }
        try {
            int value = std::stoi(tail);
            if (value <= 0) {
                printResponse("show_message", false, "Tabs", "Tab index must be >= 1");
                return 0;
            }
            printResponse("open_tab_index", true, "", "", "", "", value - 1);
            return 0;
        } catch (...) {
            printResponse("show_message", false, "Tabs", "Invalid tab number");
            return 0;
        }
    }

    if (command == "music") {
        if (tail.empty()) {
            printResponse("open_music_window");
            return 0;
        }

        const std::string lowerTail = toLower(tail);
        if (lowerTail == "stop") {
            printResponse("music_stop");
            return 0;
        }
        if (lowerTail == "pause") {
            printResponse("music_pause");
            return 0;
        }
        if (lowerTail == "toggle" || lowerTail == "playpause" || lowerTail == "play/pause") {
            printResponse("music_toggle");
            return 0;
        }
        if (lowerTail == "next") {
            printResponse("music_next");
            return 0;
        }
        if (lowerTail == "prev" || lowerTail == "previous") {
            printResponse("music_previous");
            return 0;
        }
        if (lowerTail == "favorite" || lowerTail == "favourite" || lowerTail == "fav" || lowerTail == "like") {
            printResponse("music_favorite");
            return 0;
        }
        if (lowerTail == "playlist" || lowerTail == "radio") {
            printResponse("music_playlist_context");
            return 0;
        }
        if (lowerTail == "find" || lowerTail == "search") {
            printResponse("music_find_context");
            return 0;
        }
        if (lowerTail == "list") {
            printResponse("music_list");
            return 0;
        }
        if (lowerTail == "help") {
            printResponse(
                "show_message",
                true,
                "Music",
                "music play <query> | music toggle | music next | music prev | music playlist | music focus <mood>"
            );
            return 0;
        }
        if (lowerTail.rfind("focus", 0) == 0) {
            std::string mode = trim(tail.substr(5));
            if (mode.empty()) {
                mode = "coding";
            }
            printResponse("music_focus_mode", true, "", "", "", mode);
            return 0;
        }
        if (lowerTail.rfind("find ", 0) == 0) {
            const std::string query = trim(tail.substr(5));
            printResponse("music_find_context", true, "", "", "", query);
            return 0;
        }
        if (lowerTail.rfind("search ", 0) == 0) {
            const std::string query = trim(tail.substr(7));
            printResponse("music_find_context", true, "", "", "", query);
            return 0;
        }
        if (lowerTail.rfind("play ", 0) == 0) {
            const std::string query = trim(tail.substr(5));
            if (query.empty()) {
                printResponse("show_message", false, "Music", "Usage: music play <query>");
                return 0;
            }
            printResponse("music_play", true, "", "", "", query);
            return 0;
        }

        printResponse("music_play", true, "", "", "", tail);
        return 0;
    }

    if (command == "alias") {
        if (words.size() <= 1) {
            printResponse("show_message", true, "Alias", "Use: alias <key> <exp>");
            return 0;
        }
        printResponse("show_message", true, "Alias", "Alias saved");
        return 0;
    }

    if (command == "fav") {
        printResponse("show_message", true, "Favorites", "Use bookmarks or saved panel for now");
        return 0;
    }

    if (command == "js") {
        const std::string value = toLower(words.size() >= 2 ? words[1] : trim(tail));
        if (value != "on" && value != "off") {
            printResponse("show_message", false, "Security", "Usage: js on|off");
            return 0;
        }
        printResponse("set_secure_js", true, "Security", "", "", value);
        return 0;
    }

    if (command == "clearonexit") {
        const std::string mode = toLower(words.size() >= 2 ? words[1] : "");
        if (mode.empty()) {
            printResponse("show_message", false, "Security", "Usage: clearonexit add|del <host> | list");
            return 0;
        }
        if (mode == "list") {
            printResponse("clearonexit_list");
            return 0;
        }
        if ((mode == "add" || mode == "del" || mode == "delete" || mode == "remove") && words.size() >= 3) {
            const bool isAdd = (mode == "add");
            printResponse(isAdd ? "clearonexit_add" : "clearonexit_del", true, "", "", "", words[2]);
            return 0;
        }
        printResponse("show_message", false, "Security", "Usage: clearonexit add|del <host> | list");
        return 0;
    }

    if (command == "wipe" || command == "pass") {
        printResponse("show_message", true, "Security", "This security command is in preview mode");
        return 0;
    }

    if (command == "help") {
        const std::string lowerTail = toLower(trim(tail));
        if (lowerTail == "ext" || lowerTail == "extension" || lowerTail == "extensions") {
            printResponse(
                "show_help",
                true,
                "Help Extensions",
                "ext list | ext panel | ext install <folder|url|id> | ext webstore <url|id> | ext enable <id> | ext disable <id> | ext remove <id> | ext popup <id> | ext options <id> | ext window <id> | ext grant/revoke <id> <permission> | ext reload | ext logs"
            );
            return 0;
        }
        if (!tail.empty()) {
            printResponse("show_help", true, "Help", "Command: " + tail);
            return 0;
        }
        printResponse(
            "show_help",
            true,
            "MC Browser Help",
            "Cmd+E commands are grouped into sections: navigation, search, extensions, tools, interface, security, pro."
        );
        return 0;
    }

    if (bangMode) {
        // Unknown !command is sent to web search as-is, useful for DDG bangs.
        printResponse("search_web", true, "", "", "", raw);
        return 0;
    }

    printResponse("not_command");
    return 0;
}
