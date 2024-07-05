`timescale 1ns/1ns

module testbench #(
	parameter ADDR_BITS = 8,
	parameter DATA_BITS = 8,
	parameter NUM_CONSUMERS = 8,
	parameter NUM_CHANNELS = 8,
	parameter NUM_BLOCKS = 8,
	parameter NUM_BANKS = 2,
	parameter NUM_WAYS = 4,
	parameter CACHE_BLOCK_SIZE = 1,
);
	reg clk;
	
	always #5 clk =~ clk;
    dcache_if _if(clk);
	dcache #(
        .ADDR_BITS(ADDR_BITS),
        .DATA_BITS(DATA_BITS),
        .NUM_CONSUMERS(NUM_CONSUMERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .NUM_BLOCKS(NUM_BLOCKS),
        .NUM_BANKS(NUM_BANKS),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_BLOCK_SIZE(CACHE_BLOCK_SIZE)
    ) data_cache (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(_if.consumer_read_valid),
        .consumer_read_address(_if.consumer_read_address),
        .consumer_read_ready(_if.consumer_read_ready),
        .consumer_read_data(_if.consumer_read_data),
        .consumer_write_valid(_if.consumer_write_valid),
        .consumer_write_address(_if.consumer_write_address),
        .consumer_write_data(_if.consumer_write_data),
        .consumer_write_ready(_if.consumer_write_ready),

        .controller_read_valid(_if.controller_read_valid),
        .controller_read_address(_if.controller_read_address),
        .controller_read_ready(_if.controller_read_ready),
        .controller_read_data(_if.controller_read_data),
        .controller_write_valid(_if.controller_write_valid),
        .controller_write_address(_if.controller_write_address),
        .controller_write_data(_if.controller_write_data),
        .controller_write_ready(_if.controller_write_ready)
    );

	initial begin
		clk = 0;
		// TODO: properly separate inputs and outputs
		@(negedge clk);
		$display("controller_read_valid=0x%h",_if.controller_read_valid);
		$finish;
	end

endmodule

interface dcache_if (input clk);
    // Consumer Inputs
    logic [NUM_CONSUMERS-1:0] consumer_read_valid;
    logic [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0];
    logic [NUM_CONSUMERS-1:0] consumer_write_valid;
    logic [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0];
    logic [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0];

    // Controller Inputs
    logic [NUM_CONSUMERS-1:0] controller_read_ready;
    logic [DATA_BITS-1:0] controller_read_data [NUM_CONSUMERS-1:0];
    logic [NUM_CONSUMERS-1:0] controller_write_ready;

    // Consumer Outputs
    logic [NUM_CONSUMERS-1:0] consumer_read_ready;
    logic [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0];
    logic [NUM_CONSUMERS-1:0] consumer_write_ready;

    // Controller Outputs
    logic [NUM_CONSUMERS-1:0] controller_read_valid;
    logic [ADDR_BITS-1:0] controller_read_address [NUM_CONSUMERS-1:0];
    logic [NUM_CONSUMERS-1:0] controller_write_valid;
    logic [ADDR_BITS-1:0] controller_write_address [NUM_CONSUMERS-1:0];
    logic [DATA_BITS-1:0] controller_write_data [NUM_CONSUMERS-1:0];
endinterface