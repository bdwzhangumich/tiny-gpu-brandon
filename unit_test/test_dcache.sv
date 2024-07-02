module testbench;
	reg clk;
	
	always #5 clk =~ clk;

	dcache #(
        .ADDR_BITS(8),
        .DATA_BITS(8),
        .NUM_CONSUMERS(8),
        .NUM_CHANNELS(8),
        .NUM_BLOCKS(8),
        .NUM_BANKS(2),
        .NUM_WAYS(4),
        .CACHE_BLOCK_SIZE(1)
    ) data_cache (
        .clk(clk),
        .reset(reset),

        .consumer_read_valid(consumer_read_valid),
        .consumer_read_address(consumer_read_address),
        .consumer_read_ready(consumer_read_ready),
        .consumer_read_data(consumer_read_data),
        .consumer_write_valid(consumer_write_valid),
        .consumer_write_address(consumer_write_address),
        .consumer_write_data(consumer_write_data),
        .consumer_write_ready(consumer_write_ready),

        .controller_read_valid(controller_read_valid),
        .controller_read_address(controller_read_address),
        .controller_read_ready(controller_read_ready),
        .controller_read_data(controller_read_data),
        .controller_write_valid(controller_write_valid),
        .controller_write_address(controller_write_address),
        .controller_write_data(controller_write_data),
        .controller_write_ready(controller_write_ready)
    );

	initial begin
		consumer_read_valid = 0;
		consumer_read_address = 0;
		consumer_read_ready = 0;
		consumer_read_data = 0;
		consumer_write_valid = 0;
		consumer_write_address = 0;
		consumer_write_data = 0;
		consumer_write_ready = 0;
		@(negedge clock);
		$$display("controller_read_valid=0x%0h",controller_read_valid);
	end

endmodule