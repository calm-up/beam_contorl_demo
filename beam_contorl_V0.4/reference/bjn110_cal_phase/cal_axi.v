module cal_axi(

	i_clk,
	i_rst_n,

	i_cal_start,
	i_axi_valide,
	i_cal_end,
	i_mx,
	i_my,

	i_formula_left,
	i_formula_right,

	o_phase,
	o_valide

);
	input 											i_clk;
	input 											i_rst_n;
	input 											i_cal_start;
	input 											i_axi_valide;
	input 											i_cal_end;
	input 	signed [7:0]							i_mx;
	input 	signed [7:0]							i_my;

	input 	signed [60:0]							i_formula_left;
	input 	signed [60:0]							i_formula_right;

	output		[5:0]								o_phase;
	output											o_valide;
//----------------------------------------------------------------------

	reg 											r_sym_flag;
	reg 			[7:0]							r_state;

	//reg 	signed  [60:0]							r_formula_left4; //r_formula_left3 /常数
	//reg 	signed  [60:0]							r_formula_right4;//r_formula_right3/常数
	reg 	signed  [63:0]							r_formula_add;//r_formula_left4*i_mx + r_formula_right4*i_my

	localparam IDLE = 'd0;
	localparam CALN = 'd1;//此状态为计算频率，间距和相位信息
	localparam CALM = 'd2;//此状态为依次计算每个坐标下的数值
//---------------------------------------------------------------------------------------------------------
	assign o_phase  = r_formula_add[39] ? r_formula_add[45:40] + 1'b1 : r_formula_add[45:40];
	assign o_valide = r_sym_flag;

//------------------------------------------------------------------------------------------------------------

	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			r_state <= 'd0;
		else
			case(r_state)

				IDLE	:	if(i_cal_start)
								r_state <= CALM;
							else
								r_state <= r_state;

			    CALM	:	if(i_cal_end)
								r_state <= IDLE;
							else
								r_state <= r_state;

			  default 	:	;
			endcase
	end

	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			begin
				r_formula_add <= 'd0;
				r_sym_flag    <= 'd0;
			end
		else
			case(r_state)
				IDLE	:	begin
								if(i_cal_start)
									begin
										r_formula_add <= -i_formula_left*i_mx + i_formula_right*i_my;
										r_sym_flag    <= 'd1;
									end
								else
									begin
										r_formula_add <= -i_formula_left*i_mx + i_formula_right*i_my;
										r_sym_flag    <= 'd0;
									end
							end

				CALM 	:	if(i_axi_valide)
								begin
									r_formula_add <= -i_formula_left*i_mx + i_formula_right*i_my;
									r_sym_flag    <= 'd1;
								end
							else
								begin
									r_formula_add <= r_formula_add;
									r_sym_flag    <= 'd0;
								end
			  default 	:	;
			endcase
	end

endmodule
