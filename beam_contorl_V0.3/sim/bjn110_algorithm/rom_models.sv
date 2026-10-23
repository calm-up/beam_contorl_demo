// Simulation-only asynchronous ROM adapters for the original a/spo interfaces.
// Contents are copied verbatim from the three original COE tables.
module tri_ram(input wire [13:0] a, output wire [20:0] spo);
    reg [20:0] data [0:9000];
    initial $readmemh("tri.mem", data);
    assign spo = a <= 9000 ? data[a] : 21'bx;
endmodule
module fuxing_fs(input wire [4:0] a, output wire [191:0] spo);
    reg [191:0] data [0:31];
    initial $readmemh("fs.mem", data);
    assign spo = data[a];
endmodule
module fuxing_js(input wire [4:0] a, output wire [191:0] spo);
    reg [191:0] data [0:31];
    initial $readmemh("js.mem", data);
    assign spo = data[a];
endmodule
