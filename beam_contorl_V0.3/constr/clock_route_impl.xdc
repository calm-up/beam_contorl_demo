# Temporary board-validation route: V20 is the N side and has no direct
# single-ended clock path. Only IBUF-to-BUFG is allowed to use fabric routing.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets sys_clk_i_IBUF]
