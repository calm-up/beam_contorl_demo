`timescale 1ns/1ps

// Exact Q20 sine samples from BJN110 tri_data.coe, 0.00 through 90.00 degrees.
// The asynchronous a/spo interface preserves the timing of the original tri_fun.
module tri_ram (
    input  wire [13:0] a,
    output wire [20:0] spo
);
    (* rom_style = "distributed" *) reg [20:0] data [0:9000];
`ifdef SYNTHESIS
    // Vivado resolves registered memory files by basename in synth_1.
    initial $readmemh("tri.mem", data);
`else
    initial $readmemh("rtl/rom/tri.mem", data);
`endif
    assign spo = (a <= 14'd9000) ? data[a] : 21'd0;
endmodule
