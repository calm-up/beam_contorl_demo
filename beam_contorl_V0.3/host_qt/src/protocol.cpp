#include "protocol.h"

#include <algorithm>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace beam {

namespace {
Field f(const char *key, const char *name, int start = 0, int low = 0, int high = 255) {
    return {key, name, static_cast<uint8_t>(start), static_cast<uint8_t>(low),
            static_cast<uint8_t>(high), false};
}
Field c(int value, const char *name) {
    return {"fixed", name, static_cast<uint8_t>(value), static_cast<uint8_t>(value),
            static_cast<uint8_t>(value), true};
}
Field line() { return f("line", "线阵编号", 0, 0, 7); }
Field chip() { return f("chip", "芯片索引（SDI1～4）", 0, 0, 3); }
Field channel() { return f("channel", "芯内通道编号", 0, 0, 3); }
Field enable() { return f("enable", "通道使能", 1, 0, 1); }
Field phase(const char *key, const char *name) { return f(key, name, 0, 0, 63); }
Field atten(const char *key, const char *name) { return f(key, name, 0, 0, 63); }
Field freqHi() { return f("freq_hi", "频率高字节"); }
Field freqLo() { return f("freq_lo", "频率低字节"); }
Field flashFreqHi() { return c(0, "频点序号高字节（当前固定零）"); }
Field flashFreqLo() { return f("freq_slot", "频点序号（0～31）", 0, 0, 31); }
Field pulse() { return f("pulse", "脉冲形式", 0, 0, 255); }
Field stc() { return f("stc", "STC模式", 0, 0, 3); }
Field window() { return f("window", "窗函数模式", 0, 0, 2); }
Field azHi() { return f("az_hi", "方位角高字节"); }
Field azLo() { return f("az_lo", "方位角低字节"); }
Field elHi() { return f("el_hi", "俯仰角高字节"); }
Field elLo() { return f("el_lo", "俯仰角低字节"); }
Field confirm1() { return c(0xA5, "擦除确认第1字节"); }
Field confirm2() { return c(0x5A, "擦除确认第2字节"); }
std::vector<Field> flashOrdinary(bool write) {
    return {line(), c(0, "保留字节11"), c(0, "保留字节10"),
            write ? chip() : c(0, "扇区擦除时芯片字段不参与定位"),
            write ? channel() : c(0, "扇区擦除时通道字段不参与定位"),
            write ? c(0, "串口衰减（待接入）") : c(0, "保留字节7"),
            write ? phase("tx_phase", "发射移相码") : c(0, "保留字节6"),
            write ? phase("rx_phase", "接收移相码") : c(0, "保留字节5"),
            write ? atten("tx_att", "发射衰减码") : c(0, "保留字节4"),
            write ? atten("rx_att", "接收衰减码") : c(0, "保留字节3"),
            write ? c(0, "并口衰减（待接入）") : confirm1(),
            write ? c(0, "保留字节1") : confirm2()};
}
std::vector<Field> flashMain(bool write) {
    return {c(0x11, "主路类别"), flashFreqHi(), flashFreqLo(),
            write ? chip() : c(0, "扇区擦除时芯片字段不参与定位"),
            write ? channel() : c(0, "扇区擦除时通道字段不参与定位"),
            write ? f("main_enable", "主路选择", 0, 0, 1) : c(0, "扇区擦除保留字段"),
            write ? phase("tx_phase", "发射移相码") : c(0, "保留字节6"),
            write ? phase("rx_phase", "接收移相码") : c(0, "保留字节5"),
            write ? atten("tx_att", "发射衰减码") : c(0, "保留字节4"),
            write ? atten("rx_att", "接收衰减码") : c(0, "保留字节3"),
            write ? c(0, "保留字节2") : confirm1(),
            write ? c(0, "保留字节1") : confirm2()};
}
std::vector<Field> flashCoefficient(bool write) {
    return {c(0x12, "指向系数类别"), flashFreqHi(), flashFreqLo(),
            write ? f("coef0", "系数字节0") : c(0, "保留字节9"),
            write ? f("coef1", "系数字节1") : c(0, "保留字节8"),
            write ? f("coef2", "系数字节2") : c(0, "保留字节7"),
            write ? f("coef3", "系数字节3") : c(0, "保留字节6"),
            write ? f("coef4", "系数字节4") : c(0, "保留字节5"),
            write ? f("coef5", "系数字节5") : c(0, "保留字节4"),
            write ? f("coef6", "系数字节6") : c(0, "保留字节3"),
            write ? f("coef7", "系数字节7") : confirm1(),
            write ? c(0, "保留字节1") : confirm2()};
}
std::vector<Field> flashStc(bool write) {
    return {c(0x13, "STC类别"),
            write ? f("stc_index", "STC曲线点编号", 0, 0, 128) :
                    c(0, "扇区擦除时曲线点字段不参与定位"),
            write ? atten("att", "衰减码") : c(0, "保留字节10"),
            c(0, "保留字节9"), c(0, "保留字节8"), c(0, "保留字节7"),
            c(0, "保留字节6"), c(0, "保留字节5"), c(0, "保留字节4"),
            c(0, "保留字节3"), write ? c(0, "保留字节2") : confirm1(),
            write ? c(0, "保留字节1") : confirm2()};
}

bool validPulse(uint8_t p) {
    switch (p) {
    case 0x00: case 0x01: case 0x02: case 0x11: case 0x12:
    case 0x21: case 0x31: case 0x41: case 0x51: case 0x61:
        return true;
    default: return false;
    }
}
}

const std::vector<Mode> &modes() {
    static const std::vector<Mode> all = {
        {"00 线阵复位", "通道与复位", 0x00, {f("line_mask", "线阵选择掩码", 1), c(0, "复位范围")}},
        {"40 单通道幅相", "通道与复位", 0x40,
         {line(), chip(), channel(), enable(), phase("tx_phase", "发射移相码"),
          phase("rx_phase", "接收移相码"), atten("tx_att", "发射衰减码"),
          atten("rx_att", "接收衰减码"), c(0, "串口衰减码（暂不支持）"),
          c(0, "并口衰减码（暂不支持）"), pulse(), stc(), window(), freqHi(), freqLo()}},
        {"20 波束指向", "波束与区域", 0x20,
         {freqHi(), freqLo(), azHi(), azLo(), elHi(), elLo(), window(), stc(), pulse(),
          f("beam", "波束形式", 0, 0, 1)}},
        {"A0 区域选择", "波束与区域", 0xA0,
         {f("line_mask", "线阵选择掩码", 1), f("chip_mask", "芯片选择掩码", 1, 0, 15),
          f("channel_mask", "通道选择掩码", 1, 0, 15), freqHi(), freqLo(), azHi(),
          azLo(), elHi(), elLo(), pulse()}},
        {"C0 选中位置覆盖", "波束与区域", 0xC0,
         {line(), chip(), channel(), enable(), phase("tx_phase", "发射移相码"),
          phase("rx_phase", "接收移相码"), atten("tx_att", "发射衰减码"),
          atten("rx_att", "接收衰减码"), pulse()}},
        {"E0 状态查询", "状态", 0xE0, {}},
        {"F1 擦除线阵校准扇区", "Flash维护", 0xF1, flashOrdinary(false), true},
        {"F2 写入校准记录", "Flash维护", 0xF2, flashOrdinary(true), true},
        {"F1 擦除主路频点扇区", "Flash维护", 0xF1, flashMain(false), true},
        {"F2 写入主路数据", "Flash维护", 0xF2, flashMain(true), true},
        {"F1 擦除指向系数频点扇区", "Flash维护", 0xF1, flashCoefficient(false), true},
        {"F2 写入指向系数", "Flash维护", 0xF2, flashCoefficient(true), true},
        {"F1 擦除STC扇区", "Flash维护", 0xF1, flashStc(false), true},
        {"F2 写入STC数据", "Flash维护", 0xF2, flashStc(true), true},
        {"F3 Flash重载", "Flash维护", 0xF3,
        {f("scope", "线阵0～7或类别11/12/13")}, true},
        {"F5 Flash全擦除", "Flash维护", 0xF5,
         {confirm1(), confirm2()}, true}
    };
    return all;
}

std::string validate(const Mode &mode, uint8_t array, const std::vector<uint8_t> &payload) {
    if (array != 0 && array != 1 && array != 2 && array != 0xFF)
        return "阵面选择超出范围";
    if (mode.flash && array > 1) return "Flash命令只能选择接收或发射阵面";
    if (array == 0xFF && mode.command != 0xE0) return "全局选择仅用于状态查询";
    if (array == 2 && mode.command != 0x00 && mode.command != 0xE0)
        return "本命令需分别指定接收或发射阵面";
    if (payload.size() != mode.fields.size()) return "数据区字节数不符";
    for (size_t i = 0; i < payload.size(); ++i) {
        const auto &field = mode.fields[i];
        if (payload[i] < field.minimum || payload[i] > field.maximum)
            return std::string(field.label) + "取值超出协议范围";
        if (std::string(field.key) == "pulse" && !validPulse(payload[i]))
            return "脉冲形式编码未定义";
        if (std::string(field.key) == "pulse" && (mode.command == 0x40 || mode.command == 0xC0)) {
            const uint8_t pulseCode = payload[i];
            if ((array == 0 && pulseCode != 0 && pulseCode != 0x02 && pulseCode != 0x12) ||
                (array == 1 && (pulseCode == 0x02 || pulseCode == 0x12)))
                return "脉冲形式与接收或发射阵面不匹配";
        }
        if (std::string(field.key) == "line_mask" && payload[i] == 0)
            return "线阵选择掩码不能为空";
        if ((std::string(field.key) == "chip_mask" || std::string(field.key) == "channel_mask")
            && payload[i] == 0) return "选择掩码不能为空";
        if (std::string(field.key) == "scope" && payload[i] > 7 && payload[i] != 0x11 &&
            payload[i] != 0x12 && payload[i] != 0x13) return "线阵或数据类别未定义";
    }
    return {};
}

std::vector<uint8_t> encode(const Frame &frame) {
    if (frame.payload.size() > 56) throw std::invalid_argument("数据区超过56字节");
    const uint8_t length = static_cast<uint8_t>(frame.payload.size() + 8);
    std::vector<uint8_t> bytes{0xAA, 0xDD, 0x01, length, frame.command, frame.array};
    bytes.insert(bytes.end(), frame.payload.begin(), frame.payload.end());
    unsigned sum = 0;
    for (size_t i = 2; i < bytes.size(); ++i) sum += bytes[i];
    bytes.push_back(static_cast<uint8_t>(sum));
    bytes.push_back(0x55);
    return bytes;
}

bool decode(const std::vector<uint8_t> &bytes, Frame &frame, std::string &error) {
    if (bytes.size() < 8 || bytes.size() > 64 || bytes[0] != 0xAA || bytes[1] != 0xDD) {
        error = "帧头或长度无效"; return false;
    }
    if (bytes[2] != 0x01 || bytes[3] != bytes.size() || bytes.back() != 0x55) {
        error = "版本、长度或帧尾无效"; return false;
    }
    unsigned sum = 0;
    for (size_t i = 2; i + 2 < bytes.size(); ++i) sum += bytes[i];
    if (static_cast<uint8_t>(sum) != bytes[bytes.size() - 2]) {
        error = "校验和错误"; return false;
    }
    frame.command = bytes[4]; frame.array = bytes[5];
    frame.payload.assign(bytes.begin() + 6, bytes.end() - 2);
    error.clear();
    return true;
}

std::string hex(const std::vector<uint8_t> &bytes) {
    std::ostringstream out;
    out << std::uppercase << std::hex << std::setfill('0');
    for (size_t i = 0; i < bytes.size(); ++i) {
        if (i) out << ' ';
        out << std::setw(2) << static_cast<unsigned>(bytes[i]);
    }
    return out.str();
}

std::vector<uint8_t> response(uint8_t array, uint8_t originalCommand, uint8_t status,
                              const std::vector<uint8_t> &extra) {
    Frame frame{0x7F, array, {originalCommand, status}};
    frame.payload.insert(frame.payload.end(), extra.begin(), extra.end());
    return encode(frame);
}

std::vector<Frame> FrameStream::push(const uint8_t *data, size_t count) {
    if (data && count) buffer_.insert(buffer_.end(), data, data + count);
    std::vector<Frame> found;
    while (buffer_.size() >= 2) {
        if (buffer_[0] != 0xAA || buffer_[1] != 0xDD) {
            buffer_.erase(buffer_.begin()); continue;
        }
        if (buffer_.size() < 4) break;
        const size_t length = buffer_[3];
        if (length < 8 || length > 64) { buffer_.erase(buffer_.begin()); continue; }
        if (buffer_.size() < length) break;
        Frame frame; std::string error;
        std::vector<uint8_t> candidate(buffer_.begin(), buffer_.begin() + length);
        if (decode(candidate, frame, error)) {
            found.push_back(std::move(frame));
            buffer_.erase(buffer_.begin(), buffer_.begin() + length);
        } else buffer_.erase(buffer_.begin());
    }
    if (buffer_.size() > 128) buffer_.erase(buffer_.begin(), buffer_.end() - 64);
    return found;
}

} // namespace beam
