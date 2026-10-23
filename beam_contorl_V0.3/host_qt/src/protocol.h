#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace beam {

struct Field {
    const char *key;
    const char *label;
    uint8_t initial;
    uint8_t minimum;
    uint8_t maximum;
    bool fixed = false;
};

struct Mode {
    const char *name;
    const char *group;
    uint8_t command;
    std::vector<Field> fields;
    bool flash = false;
};

struct Frame {
    uint8_t command = 0;
    uint8_t array = 0;
    std::vector<uint8_t> payload;
};

const std::vector<Mode> &modes();
std::string validate(const Mode &mode, uint8_t array, const std::vector<uint8_t> &payload);
std::vector<uint8_t> encode(const Frame &frame);
bool decode(const std::vector<uint8_t> &bytes, Frame &frame, std::string &error);
std::string hex(const std::vector<uint8_t> &bytes);
std::vector<uint8_t> response(uint8_t array, uint8_t originalCommand, uint8_t status,
                              const std::vector<uint8_t> &extra = {});

// 将串口的任意分片还原为完整 V0.3 帧；坏帧后继续寻找帧头。
class FrameStream {
public:
    std::vector<Frame> push(const uint8_t *data, size_t count);
    void clear() { buffer_.clear(); }
private:
    std::vector<uint8_t> buffer_;
};

} // namespace beam
