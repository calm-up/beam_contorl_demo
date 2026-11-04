module gen_my#(
	parameter XIANGXIAN = 'd2,
	parameter GROUP = 25
)(

	i_clk,
	i_rst_n,

	o_my
);

	input 										i_clk;
	input 										i_rst_n;


	output 			[8*GROUP-1:0]					o_my;

//----------------------------------------------------------------------

	reg 	signed	[7:0]						w_signed_my[1:25];

	assign o_my = {	w_signed_my[25],
					w_signed_my[24],w_signed_my[23],w_signed_my[22],w_signed_my[21],
					w_signed_my[20],w_signed_my[19],w_signed_my[18],w_signed_my[17],
					w_signed_my[16],w_signed_my[15],w_signed_my[14],w_signed_my[13],
					w_signed_my[12],w_signed_my[11],w_signed_my[10],w_signed_my[9],
					w_signed_my[8],w_signed_my[7],w_signed_my[6],w_signed_my[5],
					w_signed_my[4],w_signed_my[3],w_signed_my[2],w_signed_my[1]};

	integer n;

	always@(posedge i_clk)
	begin
		if(!i_rst_n)
			begin
				for(n=1;n<GROUP+1'b1;n=n+1)
									begin
										w_signed_my[n] = 1 + ((n-1)<<1);
									end
			end
		else
			case(XIANGXIAN)
				'd1 	:		begin
									for(n=1;n<GROUP+1'b1;n=n+1)
										begin
											w_signed_my[n] = 1 + ((n-1)<<1);
										end
								end
				'd2 	:		begin
									for(n=1;n<GROUP+1'b1;n=n+1)
										begin
											w_signed_my[n] = 1 + ((n-1)<<1);
										end
								end
				'd3 	:		begin
									for(n=1;n<GROUP+1'b1;n=n+1)
										begin
											w_signed_my[n] = -49 + ((n-1)<<1);
										end
								end
				'd4 	:		begin
									for(n=1;n<GROUP+1'b1;n=n+1)
										begin
											w_signed_my[n] = -49 + ((n-1)<<1);
										end
								end
			  default 	:	begin
								for(n=1;n<GROUP+1'b1;n=n+1)
									begin
										w_signed_my[n] = 1 + ((n-1)<<1);
									end
							end
			endcase
	end
endmodule
