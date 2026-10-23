#include "protocol.h"

#include <cassert>
#include <iostream>

int main() {
    using namespace beam;
    assert(modes().size() == 16);
    for (const auto &mode : modes()) {
        std::vector<uint8_t> data;
        for (const auto &field : mode.fields) data.push_back(field.initial);
        assert(validate(mode, 0, data).empty());
        Frame original{mode.command, 0, data}, decoded;
        std::string error;
        auto bytes = encode(original);
        assert(bytes.size() == data.size() + 8);
        assert(decode(bytes, decoded, error));
        assert(decoded.command == original.command && decoded.payload == data);
        bytes[bytes.size() - 2] ^= 1;
        assert(!decode(bytes, decoded, error));
        if (mode.command == 0xF1 || mode.command == 0xF2) {
            assert(data.size() == 12);
            assert(data[0] <= 7 || data[0] == 0x11 ||
                   data[0] == 0x12 || data[0] == 0x13);
        }
    }
    for (const auto &mode : modes()) assert(mode.command != 0xD0);
    const auto &channelMode = modes()[1];
    std::vector<uint8_t> maxAtt;
    for (const auto &field : channelMode.fields) maxAtt.push_back(field.initial);
    maxAtt[7] = 63;
    assert(validate(channelMode, 0, maxAtt).empty());
    maxAtt[10] = 0x11;
    assert(!validate(channelMode, 0, maxAtt).empty());
    maxAtt[10] = 0x12;
    assert(validate(channelMode, 0, maxAtt).empty());
    maxAtt[10] = 0x13;
    assert(!validate(channelMode, 0, maxAtt).empty());
    for (const auto &mode : modes()) {
        if (mode.command != 0xF1) continue;
        assert(mode.fields[10].initial == 0xA5 && mode.fields[11].initial == 0x5A);
    }

    const auto sample = encode(Frame{0x40, 0,
        {0x00,0x02,0x01,0x01,0x00,0x10,0x00,0x14,0x00,0x00,0x02,0x00,0x00,0x00,0x00}});
    assert(hex(sample) ==
        "AA DD 01 17 40 00 00 02 01 01 00 10 00 14 00 00 02 00 00 00 00 82 55");
    assert(hex(response(0, 0x40, 0)) == "AA DD 01 0A 7F 00 40 00 CA 55");

    FrameStream stream;
    auto first = stream.push(sample.data(), 3);
    assert(first.empty());
    auto second = stream.push(sample.data() + 3, sample.size() - 3);
    assert(second.size() == 1 && second[0].payload[5] == 0x10);
    auto wrong = sample; wrong[wrong.size() - 2] ^= 1;
    wrong.insert(wrong.end(), sample.begin(), sample.end());
    auto recovered = stream.push(wrong.data(), wrong.size());
    assert(recovered.size() == 1);

    std::cout << "16 modes, BJN110 Flash positions, pulses, framing, checksum: PASS\n";
}
