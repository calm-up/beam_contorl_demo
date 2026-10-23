module wave_veight(

	i_clk,
	i_rst_n,

	i_wave_form,

	i_weight_addr,
	o_fuxing_fs_s,
	o_fuxing_js_s
);
	input 							i_clk;
	input 							i_rst_n;

	input 		[7:0]				i_wave_form;

	input		[7:0]				i_weight_addr;
	output reg	[6*32-1:0]			o_fuxing_fs_s;
	output reg	[6*32-1:0]			o_fuxing_js_s;

//--------------------------------------------------------------

	wire		[6*32-1:0]			w_fs_phase;
	wire		[6*32-1:0]			w_js_phase;
	wire		[4:0]				w_weight_addr;

	assign w_weight_addr = i_weight_addr-1'b1;

	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			begin
				o_fuxing_fs_s <= 0;
			    o_fuxing_js_s <= 0;
			end
		else
			if(i_wave_form==8'h01)
				begin
					o_fuxing_fs_s <= w_fs_phase;
				    o_fuxing_js_s <= w_js_phase;
				end
			else
				begin
					o_fuxing_fs_s <= 0;
					o_fuxing_js_s <= 0;
				end
	end

//---------------------------------------------------------

	fuxing_fs FUXING_FS (
		.a		(w_weight_addr),        // input wire [4 : 0] a
		.spo	(w_fs_phase)  // output wire [191 : 0] qspo
);

	fuxing_js FUXING_JS (
		.a		(w_weight_addr),        // input wire [4 : 0] a
		.spo	(w_js_phase)  // output wire [191 : 0] qspo
);



endmodule
