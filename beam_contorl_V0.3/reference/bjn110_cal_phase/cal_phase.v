module cal_phase#(
	parameter X_DIS = 47,//*100
	parameter Y_DIS = 54,//*100
	parameter GROUP = 25
	//坐标信息为13579
)(

	i_clk,
	i_clk_25m,
	i_rst_n,

	i_cal_start,
	i_wave_form,//赋形
	i_fre_value,
	i_cal_fwrecv_phase,
	i_cal_fyrecv_phase,
    i_cal_fwtran_phase,
    i_cal_fytran_phase,

	o_cal_recvdata,
	o_cal_trandata,
	o_cal_group,
	o_cal_valide

);

	input 											i_clk;
	input 											i_clk_25m;
	input 											i_rst_n;

	input 											i_cal_start;
	input 			[7:0]							i_wave_form;
	input 			[15:0]							i_fre_value;
	input signed	[15:0]							i_cal_fwrecv_phase;
	input signed	[15:0]							i_cal_fyrecv_phase;
	input signed	[15:0]							i_cal_fwtran_phase;
	input signed	[15:0]							i_cal_fytran_phase;

	output 			[32*6-1:0]						o_cal_recvdata;
	output 			[32*6-1:0]						o_cal_trandata;//32个阵元
	output 			[7:0]							o_cal_group;//计算的哪一组
	output 											o_cal_valide;

//--------------------------------------------------------------------

	wire 	[6*32-1:0]								w_fuxing_fs_s;
	wire 	[6*32-1:0]								w_fuxing_js_s;

	// wire 	[32*6-1:0]									w_fuxing_fs_m;
	// wire 	[32*6-1:0]									w_fuxing_js_m;

	wire 	[5:0]									w_cal_recvphase[1:32];
	wire 	[5:0]									w_cal_tranphase[1:32];
	wire 											w_cal_valide[1:32];
	wire 	[7:0]									w_cal_group;
	// wire	[32*6-1:0]								w_weight_phase;

	wire 	[5:0]									w_add_recvphase[1:32];
	wire 	[5:0]									w_add_tranphase[1:32];

	wire 	signed [7:0]							w_mx;
	wire 	 	   [8*32-1:0]						w_my;

	wire 		   [7:0]							w_signedmy[1:32];
	wire  	signed [21:0]							w_sin_recvfw;
	wire  	signed [21:0]							w_cos_recvfw;
	wire  	signed [21:0]							w_sin_recvfy;
	wire  	signed [21:0]							w_cos_recvfy;

	wire  	signed [21:0]							w_sin_tranfw;
	wire  	signed [21:0]							w_cos_tranfw;
	wire  	signed [21:0]							w_sin_tranfy;
	wire  	signed [21:0]							w_cos_tranfy;

	wire 	signed [60:0]							w_formula_recvleft;
    wire 	signed [60:0]							w_formula_recvright;
	wire 	signed [60:0]							w_formula_tranleft;
    wire 	signed [60:0]							w_formula_tranright;

	wire 											w_formula_valide;
	wire 											w_cal_end;

	reg 											w_cal_valide_flag1;
	reg 											w_cal_valide_flag2;

	reg 											r_tri_valide;

	reg												r_flag1;
	reg												r_flag2;
	wire											w_pose_valide;
	genvar n;

	assign o_cal_group  = w_cal_group;
	assign o_cal_valide = !r_flag2 && r_flag1;//跨时钟域的同步

	assign o_cal_recvdata = {
								w_add_recvphase[32],w_add_recvphase[31],w_add_recvphase[30],w_add_recvphase[29],
								w_add_recvphase[28],w_add_recvphase[27],w_add_recvphase[26],w_add_recvphase[25],

								w_add_recvphase[24],w_add_recvphase[23],w_add_recvphase[22],w_add_recvphase[21],
								w_add_recvphase[20],w_add_recvphase[19],w_add_recvphase[18],w_add_recvphase[17],
								w_add_recvphase[16],w_add_recvphase[15],w_add_recvphase[14],w_add_recvphase[13],
								w_add_recvphase[12],w_add_recvphase[11],w_add_recvphase[10],w_add_recvphase[9],
								w_add_recvphase[8] ,w_add_recvphase[7] ,w_add_recvphase[6] ,w_add_recvphase[5],
								w_add_recvphase[4] ,w_add_recvphase[3] ,w_add_recvphase[2] ,w_add_recvphase[1]
							};

	assign o_cal_trandata = {
								w_add_tranphase[32],w_add_tranphase[31],w_add_tranphase[30],w_add_tranphase[29],
								w_add_tranphase[28],w_add_tranphase[27],w_add_tranphase[26],w_add_tranphase[25],
								w_add_tranphase[24],w_add_tranphase[23],w_add_tranphase[22],w_add_tranphase[21],
								w_add_tranphase[20],w_add_tranphase[19],w_add_tranphase[18],w_add_tranphase[17],
								w_add_tranphase[16],w_add_tranphase[15],w_add_tranphase[14],w_add_tranphase[13],
								w_add_tranphase[12],w_add_tranphase[11],w_add_tranphase[10],w_add_tranphase[9],
								w_add_tranphase[8] ,w_add_tranphase[7] ,w_add_tranphase[6] ,w_add_tranphase[5],
								w_add_tranphase[4] ,w_add_tranphase[3] ,w_add_tranphase[2] ,w_add_tranphase[1]
							};

	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			begin
				r_flag1 <= 'd0;
			    r_flag2 <= 'd0;
			end
		else
			begin
				r_flag1 <= w_cal_valide[1];
			    r_flag2 <=r_flag1;
			end
	end


//--------------------------------------------------------------------
	tri_fun RECV_TRI_FUN(

		.i_clk				(i_clk),
		.i_rst_n			(i_rst_n),

		.i_phase_fw			(i_cal_fwrecv_phase),
		.i_phase_fy			(i_cal_fyrecv_phase),
		.i_valide			(i_cal_start),

		.o_sin_fw			(w_sin_recvfw),
		.o_cos_fw			(w_cos_recvfw),
		.o_sin_fy			(w_sin_recvfy),
		.o_cos_fy			(w_cos_recvfy),
		.o_tri_valide		(w_tri_valide)

);

	// tri_fun TRAN_TRI_FUN(

		// .i_clk				(i_clk),
		// .i_rst_n			(i_rst_n),

		// .i_phase_fw			(i_cal_fwtran_phase),
		// .i_phase_fy			(i_cal_fytran_phase),
		// .i_valide			(i_cal_start),

		// .o_sin_fw			(w_sin_tranfw),
		// .o_cos_fw			(w_cos_tranfw),
		// .o_sin_fy			(w_sin_tranfy),
		// .o_cos_fy			(w_cos_tranfy),
		// .o_tri_valide		( )

// );

	group_gen GROUP_GEN(

		.i_clk				(i_clk_25m),
		.i_rst_n			(i_rst_n),

		.i_next				(w_cal_valide[1]),
		.o_cal_end			(w_cal_end),
		.o_group_num		(w_cal_group),
		.o_signed_axi		(w_mx),
		.o_valide			(w_axi_valide)

);
	wave_veight WAVE_WEIGHT(

		.i_clk				(i_clk),
		.i_rst_n			(i_rst_n),

		.i_wave_form		(i_wave_form),

		.i_weight_addr		(w_cal_group),
		.o_fuxing_fs_s		(w_fuxing_fs_s),
		.o_fuxing_js_s      (w_fuxing_js_s)
);


	cal_formula#(
		.X_DIS(X_DIS),//*10
		.Y_DIS(Y_DIS)//*10
	)CAL_X_RECV(

		.i_clk						(i_clk_25m),
		.i_rst_n					(i_rst_n),

		.i_fre_value				(i_fre_value),
		.i_sin_fw					(w_sin_recvfw),
		.i_cos_fw					(w_cos_recvfw),
		.i_sin_fy					(w_sin_recvfy),
		.i_cos_fy					(w_cos_recvfy),
		.i_cal_start				(w_tri_valide),
		.i_cal_end					(w_cal_end),

		.o_formula_left				(w_formula_recvleft	),
		.o_formula_right			(w_formula_recvright),
		.o_formula_valide			(w_formula_valide)
	);

	// cal_formula#(
		// .X_DIS(X_DIS),//*10
		// .Y_DIS(Y_DIS)//*10
	// )CAL_X_TRAN(

		// .i_clk						(i_clk_25m),
		// .i_rst_n					(i_rst_n),

		// .i_fre_value				(i_fre_value),
		// .i_sin_fw					(w_sin_tranfw),
		// .i_cos_fw					(w_cos_tranfw),
		// .i_sin_fy					(w_sin_tranfy),
		// .i_cos_fy					(w_cos_tranfy),
		// .i_cal_start				(w_tri_valide),
		// .i_cal_end					(w_cal_end),

		// .o_formula_left				(w_formula_tranleft	),
		// .o_formula_right			(w_formula_tranright),
		// .o_formula_valide			( )
	// );


	generate
		for(n=1;n<33;n=n+1)
			begin
				assign w_signedmy[n]      = -33+(2*n);
				assign w_add_recvphase[n] = w_cal_recvphase[n]+w_fuxing_js_s[(n*6-1): (n-1)*6];
				assign w_add_tranphase[n] = w_cal_recvphase[n]+w_fuxing_fs_s[(n*6-1): (n-1)*6];

				cal_axi CAL_ADD_RECV(

					.i_clk						(i_clk_25m),
					.i_rst_n					(i_rst_n),

					.i_mx						(w_mx),
					.i_my						(w_signedmy[n]),
					.i_cal_end 					(w_cal_end),
					.i_formula_left	            (w_formula_recvleft	),
					.i_formula_right            (w_formula_recvright),
					.i_cal_start				(w_formula_valide),
					.i_axi_valide				(w_axi_valide),

					.o_phase					(w_cal_recvphase[n]),
					.o_valide					(w_cal_valide[n])
				);

				// cal_axi CAL_ADD_TRAN(

					// .i_clk						(i_clk),
					// .i_rst_n					(i_rst_n),

					// .i_mx						(w_mx),
					// .i_my						(w_signedmy[n]),
					// .i_cal_end 					(w_cal_end),
					// .i_formula_left	            (w_formula_tranleft	),
					// .i_formula_right            (w_formula_tranright ),
					// .i_cal_start				(w_formula_valide),
					// .i_axi_valide				(w_axi_valide),

					// .o_phase					(w_cal_tranphase[n]),
					// .o_valide					()
				// );
			end
	endgenerate

endmodule
