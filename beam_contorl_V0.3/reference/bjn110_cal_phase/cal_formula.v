module cal_formula#(
	parameter X_DIS 	= 47,//*10
	parameter Y_DIS 	= 54,//*10
	parameter Y_ZB  	= 3,//Y轴的坐标
	parameter X_ZB		= 1//X轴坐标
)(

	i_clk,
	i_rst_n,

	i_fre_value,
	i_sin_fw,
	i_cos_fw,
	i_sin_fy,
	i_cos_fy,
	i_cal_start,
	i_cal_end,

	o_formula_left,
	o_formula_right,
	o_formula_valide
);

	input 										i_clk;
	input 										i_rst_n;

	input 	[15:0]								i_fre_value;

	input 	signed [21:0]						i_sin_fw;
	input 	signed [21:0]						i_cos_fw;
	input 	signed [21:0]						i_sin_fy;
	input 	signed [21:0]                       i_cos_fy;

	input 										i_cal_start;
	input 										i_cal_end;

	output 	signed [60:0]						o_formula_left;
	output 	signed [60:0]						o_formula_right;
	output 										o_formula_valide;



//----------------------------------------------------------------------------

	reg 			[5:1]					r_sym_flag;//四级同步标志
	reg 			[7:0]					r_state;
	reg 			[7:0]					r_cnt_zb;//坐标计数器

	reg 	signed	[43:0]					r_formula_left1; //sin * cos
	reg 	signed	[43:0]					r_formula_right1;//cos *2^20
	reg 	signed	[54:0]					r_formula_left2; //r_formula_left1 *DIS
	reg 	signed	[54:0]					r_formula_right2;//r_formula_right1*DIS
	reg 	signed	[66:0]					r_formula_left3; //r_formula_left2 *FRE
	reg 	signed	[66:0]					r_formula_right3;//r_formula_right2*FRE
	reg 	signed  [72:0]					r_formula_left4; //r_formula_left3 /常数
	reg 	signed  [72:0]					r_formula_right4;//r_formula_right3/常数
/* 	reg 	signed  [63:0]					r_formula_add;//r_formula_left4*i_mx + r_formula_right4*i_my
 */
	localparam IDLE = 'd0;
	localparam CALN = 'd1;//此状态为计算频率，间距和相位信息
	localparam CALM = 'd2;//此状态为依次计算每个坐标下的数值
//---------------------------------------------------------------------------------------------------------
/* 	assign o_phase  = r_formula_add[27] ? r_formula_add[32:28] + 1'b1 : r_formula_add[32:28];
	assign o_valide = r_sym_flag[5]; */

	assign o_formula_left   = r_formula_left4;
	assign o_formula_right  = r_formula_right4;
	assign o_formula_valide = r_sym_flag[4];

//------------------------------------------------------------------------------------------------------------
	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			r_state <= 'd0;
		else
			case(r_state)

				IDLE	:	if(i_cal_start)
								r_state <= CALN;
							else
								r_state <= r_state;

			    CALN	:	if(i_cal_end)
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
				r_sym_flag		<= 'd0;
				r_cnt_zb 		<= 'd0;
				r_formula_left1 <= 'd0;
				r_formula_right1<= 'd0;
				r_formula_left2 <= 'd0;
				r_formula_right2<= 'd0;
				r_formula_left3 <= 'd0;
				r_formula_right3<= 'd0;
				r_formula_left4 <= 'd0;
				r_formula_right4<= 'd0;
			end
		else
			case(r_state)
				IDLE	:	begin
								r_sym_flag[5:2]	<= 'd0;
								r_formula_left2 <= r_formula_left2 ;
								r_formula_right2<= r_formula_right2;
								r_formula_left3 <= r_formula_left3 ;
								r_formula_right3<= r_formula_right3;
								r_formula_left4 <= r_formula_left4 ;
								r_formula_right4<= r_formula_right4;
								if(i_cal_start)
									begin
										r_formula_left1 <= ($signed(i_sin_fw)) * ($signed(i_cos_fy));
										r_formula_right1<= i_sin_fy<<<20;//结果的小数点后1位为r_formula_right1[39]
										r_sym_flag[1]	<= 'd1;
									end
								else
									begin
										r_formula_left1 <= r_formula_left1;
									    r_formula_right1<= r_formula_right1;
										r_sym_flag[1]	<= 'd0;
									end
							end

				CALN	:	begin
								if(r_sym_flag[1])
									begin
										r_sym_flag[2] <= 'D1;
										r_sym_flag[1] <= 'd0;
										r_formula_left2 <= ($signed(r_formula_left1))* X_DIS;
									    r_formula_right2<= ($signed(r_formula_right1))* Y_DIS;
									end
								else
									begin
										r_sym_flag[2] <= 'D0;
										r_sym_flag[1] <= 'd1;
										r_formula_left2 <= r_formula_left2 ;
									    r_formula_right2<= r_formula_right2;
									end

								if(r_sym_flag[2])
									begin
										r_sym_flag[3]   <= 'D1;
										r_formula_left3 <= $signed(r_formula_left2)*$signed(i_fre_value);
									    r_formula_right3<= $signed(r_formula_right2)*$signed(i_fre_value);
									end
								else
									begin
										r_sym_flag[3]   <= 'D0;
										r_formula_left3 <= r_formula_left3 ;
									    r_formula_right3<= r_formula_right3;
									end

								if(r_sym_flag[3])
									begin
										r_sym_flag[4]   <= 'D1;
										r_formula_left4 <= ($signed(r_formula_left3))/$signed('d9375);//频率10MHZ步进
									    r_formula_right4<= ($signed(r_formula_right3))/$signed('d9375);//小数点右移18位
									end// 非2进制的乘除 (f*10^6)/(3*10^8*100_00) = /3*10^3  3000=375 *2^3
								else
									begin
										r_sym_flag[4]   <= 'd0;
										r_formula_left4 <= r_formula_left4;
									    r_formula_right4<= r_formula_right4;
									end
							end
			   default 	:	;
			endcase
	end


endmodule
