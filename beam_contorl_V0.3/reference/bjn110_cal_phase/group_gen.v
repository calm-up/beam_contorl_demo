module group_gen(

	i_clk,
	i_rst_n,

	i_next,
	o_cal_end,

	o_group_num,
	o_signed_axi,
	o_valide

);

	input 									i_clk;
	input 									i_rst_n;

	input 									i_next;
	output reg								o_cal_end;

	output reg			[7:0]				o_group_num;
	output 		signed  [7:0]				o_signed_axi;//输出的坐标
	output reg								o_valide;

//----------------------------------------------------------------

	reg signed 		[7:0]					w_start_axi;

	assign o_signed_axi = -31 + ((o_group_num-1)<<1);//起始坐标为最左边的坐标



	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			begin
				o_group_num <= 1;
				o_valide	<= 'd0;
				o_cal_end   <= 'd0 ;
			end
		else
			if(i_next)
				if(o_group_num==32)
					begin
						o_group_num <= 'd1;
						o_valide <= 'd0;
						o_cal_end <='d1;
					end
				else
					begin
						o_group_num <= o_group_num + 1'b1;
						o_valide <= 'd1;
						o_cal_end <='d0;
					end
			else
				begin
					o_group_num <= o_group_num;
					o_valide 	<= 'd0;
					o_cal_end 	<= 'd0;
				end
	end

endmodule
