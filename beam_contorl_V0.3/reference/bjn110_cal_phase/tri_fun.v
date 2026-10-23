module tri_fun(

	i_clk,
	i_rst_n,

	i_phase_fw,
	i_phase_fy,
	i_valide,

	o_sin_fw,
	o_cos_fw,
	o_sin_fy,
	o_cos_fy,
	o_tri_valide

);

	input 									i_clk;
	input 									i_rst_n;

	input 	signed		[15:0]				i_phase_fw;
	input 	signed		[15:0]				i_phase_fy;
	input 									i_valide;

	output 	signed		[21:0]				o_sin_fw;
	output 	signed		[21:0]				o_cos_fw;
	output 	signed		[21:0]				o_sin_fy;
	output 	signed		[21:0]				o_cos_fy;
	output 									o_tri_valide;
//--------------------------------------------------------------------------------

	reg 				[7:0]				r_state;

	reg 		 		[21:0]				r_sin_fw;
	reg 		 		[21:0]				r_cos_fw;
	reg 		 		[21:0]				r_sin_fy;
	reg 		 		[21:0]				r_cos_fy;
	reg 				[13:0]				r_tri_addr;

	reg 									r_tri_valide;

	wire				[20:0]				w_rom_data;
	wire				[13:0]				w_sinfy_addr;
	wire				[13:0]				w_sinfw_addr;
	wire				[13:0]				w_cosfy_addr;
	wire				[13:0]				w_cosfw_addr;

	assign w_sinfy_addr = (i_phase_fy<0)? (-i_phase_fy):i_phase_fy;
	assign w_cosfy_addr = (i_phase_fy<0)? (9000+i_phase_fy):(9000-i_phase_fy);

	assign w_sinfw_addr = (i_phase_fw<0)? (-i_phase_fw):i_phase_fw;
	assign w_cosfw_addr = (i_phase_fw<0)? (9000+i_phase_fw):(9000-i_phase_fw);

	assign o_sin_fw = r_sin_fw;//sin值计算时有符号，无符号转换
	assign o_cos_fw = r_cos_fw;
	assign o_sin_fy = r_sin_fy;
	assign o_cos_fy = r_cos_fy;
	assign o_tri_valide = r_tri_valide;
//--------------------------------------------------------------------------------


	localparam S0 = 'd0;
	localparam S1 = 'd1;
	localparam S2 = 'd2;
	localparam S3 = 'd3;
	localparam S4 = 'd4;
	localparam S5 = 'd5;
	localparam S6 = 'd6;
	localparam S7 = 'd7;


//--------------------------------------------------------------------------------

	tri_ram TRI_RAM(
		.a			(r_tri_addr), // input [13 : 0] addra
		.spo		(w_rom_data) // output [20 : 0] douta
);


	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			begin
				r_sin_fw <= 'd0;
				r_cos_fw <= 'd0;
			    r_sin_fy <= 'd0;
			    r_cos_fy <= 'd0;
				r_tri_addr <= 'd0;
				r_tri_valide <= 'd0;
				r_state <= 'd0;
			end
		else
			case(r_state)
				S0		:	begin//除了状态转移和同步标志信号外,全部数据信号保持
								r_tri_valide <= 'd0;
								r_cos_fw <=r_cos_fw ;
								r_cos_fy <=r_cos_fy ;
								r_sin_fy <=r_sin_fy ;
								r_sin_fw <=r_sin_fw ;

								if(i_valide)
									r_state <= S1;
								else
									r_state <= 'd0;
							end

				S1		:	begin//读取第一个sinfy的数据
								r_tri_addr <= w_sinfy_addr;
								r_state <= S2;
							end

				S2		:	begin
								r_tri_addr <= w_cosfy_addr;
								r_state <= S3;
								r_sin_fy <= (i_phase_fy<0)? ~{1'b0,w_rom_data} +1'b1 : {1'b0,w_rom_data};
								r_sin_fw <= r_sin_fw;
								r_cos_fw <= r_cos_fw;
								r_cos_fy <= r_cos_fy;
							end

				S3		:	begin
								r_tri_addr <= w_sinfw_addr;
								r_state <= S4;
								r_sin_fy <= r_sin_fy;
								r_cos_fy <= w_rom_data;
								r_sin_fw <= r_sin_fw;
								r_cos_fw <= r_cos_fw;
							end

			    S4		:	begin
								r_tri_addr <= w_cosfw_addr;
								r_state <= S5;
								r_cos_fy <= r_cos_fy;
								r_sin_fw <= (i_phase_fw<0)? ~{1'b0,w_rom_data} +1'b1 : {1'b0,w_rom_data};;
								r_sin_fy <= r_sin_fy;
								r_cos_fw <= r_cos_fw;
							end

			    S5		:	begin
								r_tri_addr <= w_cosfw_addr;
								r_state <= S6;
								r_sin_fw <= r_sin_fw;
								r_cos_fy <= r_cos_fy;
								r_sin_fy <= r_sin_fy;
								r_cos_fw <= w_rom_data;
							end

				S6 		:	begin
								r_tri_addr <= r_tri_addr;
								r_cos_fw <= w_rom_data;
								r_cos_fy <= r_cos_fy;
								r_sin_fy <= r_sin_fy;
								r_sin_fw <= r_sin_fw;
								r_tri_valide <= 'd1;
								r_state <= S7;
							end
				S7		:	begin
								r_tri_addr <= r_tri_addr;
								r_cos_fw <= w_rom_data;
								r_cos_fy <= r_cos_fy;
								r_sin_fy <= r_sin_fy;
								r_sin_fw <= r_sin_fw;
								r_tri_valide <= 'd1;
								r_state <= S0;
							end
			  default 	:	;
			endcase
	end

endmodule
