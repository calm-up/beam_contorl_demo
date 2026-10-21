# The step-3 shell intentionally drives 160 board outputs to safe constants.
# Suppress the per-bit duplicate message; the design intent is documented and
# checked by the smoke test. Do not carry this suppression into functional RTL.
set_msg_config -id {Synth 8-3917} -suppress
