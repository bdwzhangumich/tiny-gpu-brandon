`timescale 1ns/1ns

`define ADDR_BITS 8
`define DATA_BITS 8
`define NUM_CONSUMERS 8
`define NUM_CHANNELS 8
`define NUM_BLOCKS 8
`define NUM_BANKS 2
`define NUM_WAYS 4
`define CACHE_BLOCK_SIZE 1

`define half_cycle_length 5

// sv2v has bug which makes connecting ports by name for this not simulate correctly
`define check_output compare_output_interfaces ( \
clk, \
out_if.consumer_read_ready, \
out_if.consumer_read_data, \
out_if.consumer_write_ready, \
out_if.controller_read_valid, \
out_if.controller_read_address, \
out_if.controller_write_valid, \
out_if.controller_write_address, \
out_if.controller_write_data, \
expected_out_if.consumer_read_ready, \
expected_out_if.consumer_read_data, \
expected_out_if.consumer_write_ready, \
expected_out_if.controller_read_valid, \
expected_out_if.controller_read_address, \
expected_out_if.controller_write_valid, \
expected_out_if.controller_write_address, \
expected_out_if.controller_write_data, \
failed \
);

`define compare_expected(port, port_string) if (``port`` !== expected_``port``) begin \
        $display ( \
            "Failure at Cycle %0t: %s=0x%0h expected_%s=0x%0h", \
                $time/2/`half_cycle_length, port_string, ``port``, port_string, expected_``port`` \
            ); \
            failed = 1; \
        end

module testbench #(
    parameter ADDR_BITS = `ADDR_BITS,
    parameter DATA_BITS = `DATA_BITS,
    parameter NUM_CONSUMERS = `NUM_CONSUMERS,
    parameter NUM_CHANNELS = `NUM_CHANNELS,
    parameter NUM_BLOCKS = `NUM_BLOCKS,
    parameter NUM_BANKS = `NUM_BANKS,
    parameter NUM_WAYS = `NUM_WAYS,
    parameter CACHE_BLOCK_SIZE = `CACHE_BLOCK_SIZE,
);
    reg clk;
    reg failed;
    
    always #`half_cycle_length clk =~ clk;
    dcache_input_if #(
        .ADDR_BITS(ADDR_BITS),
        .DATA_BITS(DATA_BITS),
        .NUM_CONSUMERS(NUM_CONSUMERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .NUM_BLOCKS(NUM_BLOCKS),
        .NUM_BANKS(NUM_BANKS),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_BLOCK_SIZE(CACHE_BLOCK_SIZE)
    ) in_if(clk);
    dcache_output_if #(
        .ADDR_BITS(ADDR_BITS),
        .DATA_BITS(DATA_BITS),
        .NUM_CONSUMERS(NUM_CONSUMERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .NUM_BLOCKS(NUM_BLOCKS),
        .NUM_BANKS(NUM_BANKS),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_BLOCK_SIZE(CACHE_BLOCK_SIZE)
    ) out_if(clk);
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
        .reset(in_if.reset),

        .consumer_read_valid(in_if.consumer_read_valid),
        .consumer_read_address(in_if.consumer_read_address),
        .consumer_read_ready(out_if.consumer_read_ready),
        .consumer_read_data(out_if.consumer_read_data),
        .consumer_write_valid(in_if.consumer_write_valid),
        .consumer_write_address(in_if.consumer_write_address),
        .consumer_write_data(in_if.consumer_write_data),
        .consumer_write_ready(out_if.consumer_write_ready),

        .controller_read_valid(out_if.controller_read_valid),
        .controller_read_address(out_if.controller_read_address),
        .controller_read_ready(in_if.controller_read_ready),
        .controller_read_data(in_if.controller_read_data),
        .controller_write_valid(out_if.controller_write_valid),
        .controller_write_address(out_if.controller_write_address),
        .controller_write_data(out_if.controller_write_data),
        .controller_write_ready(in_if.controller_write_ready)
    );

    dcache_output_if #(
        .ADDR_BITS(ADDR_BITS),
        .DATA_BITS(DATA_BITS),
        .NUM_CONSUMERS(NUM_CONSUMERS),
        .NUM_CHANNELS(NUM_CHANNELS),
        .NUM_BLOCKS(NUM_BLOCKS),
        .NUM_BANKS(NUM_BANKS),
        .NUM_WAYS(NUM_WAYS),
        .CACHE_BLOCK_SIZE(CACHE_BLOCK_SIZE)
    ) expected_out_if(clk);

    initial begin
        $dumpvars(2,data_cache);
        clk = 0;
        failed = 0;

        // Test 0
        // Tests one load and one store
        $display("Test 0 begin");
        fork
            // driver
            // doesnt seem possible to drive using a task with sv2v
            begin
                in_if.reset = 1;
                in_if.consumer_read_valid = 0;
                in_if.consumer_read_address = 0;
                in_if.consumer_write_valid = 0;
                in_if.consumer_write_address = 0;
                in_if.consumer_write_data = 0;
                in_if.controller_read_ready = 0;
                in_if.controller_read_data = 0;
                in_if.controller_write_ready = 0;
                @(negedge clk); // Cycle 1
                in_if.reset = 0;
                // request load from dcache
                in_if.consumer_read_valid[0] = 1;
                in_if.consumer_read_address[0] = 'hFF;
                // request store from dcache
                in_if.consumer_write_valid[1] = 1;
                in_if.consumer_write_address[1] = 'hF0;
                in_if.consumer_write_data[1] = 'hF0;
                @(negedge clk); // Cycle 2
                // give dcache data from memory controller
                in_if.controller_read_ready[0] = 1;
                in_if.controller_read_data[0] = 'hFF;
                in_if.controller_read_ready[1] = 1;
                in_if.controller_read_data[1] = 'h00;
                @(negedge clk); // Cycle 3
                @(negedge clk); // Cycle 4
                // memory controller stops driving in response to acks
                in_if.controller_read_ready = 0;
                in_if.controller_read_data = 0;
            end

            // scoreboard
            begin
                expected_out_if.consumer_read_ready = 0;
                expected_out_if.consumer_read_data = 0;
                expected_out_if.consumer_write_ready = 0;
                expected_out_if.controller_read_valid = 0;
                expected_out_if.controller_read_address = 0;
                expected_out_if.controller_write_valid = 0;
                expected_out_if.controller_write_address = 0;
                expected_out_if.controller_write_data = 0;
                @(negedge clk); // Cycle 1
                `check_output;
                @(negedge clk); // Cycle 2
                // dcache forwards load and store to memory controller
                expected_out_if.controller_read_valid[0] = 1;
                expected_out_if.controller_read_address[0] = 'hFF;
                expected_out_if.controller_read_valid[1] = 1;
                expected_out_if.controller_read_address[1] = 'hF0;
                `check_output;
                @(negedge clk); // Cycle 3
                // dcache copies data to banks and gives ack to memory controller
                expected_out_if.controller_read_valid[1:0] = 0;
                `check_output;
                @(negedge clk); // Cycle 4
                // dcache responds to load and store from consumers
                expected_out_if.consumer_read_ready[0] = 1;
                expected_out_if.consumer_read_data[0] = 'hFF;
                expected_out_if.consumer_write_ready[1] = 1;
                `check_output;
            end
        join
        $display("Test 0 end");

        if (failed === 0)
            $display("Passed!");
        else
            $display("Failed!");
        $finish;
    end

endmodule

task compare_output_interfaces;
    input clk;
    // Consumer Outputs
    input [`NUM_CONSUMERS-1:0] consumer_read_ready;
    input [`DATA_BITS-1:0] consumer_read_data [`NUM_CONSUMERS-1:0];
    input [`NUM_CONSUMERS-1:0] consumer_write_ready;
    // Controller Outputs
    input [`NUM_CONSUMERS-1:0] controller_read_valid;
    input [`ADDR_BITS-1:0] controller_read_address [`NUM_CONSUMERS-1:0];
    input [`NUM_CONSUMERS-1:0] controller_write_valid;
    input [`ADDR_BITS-1:0] controller_write_address [`NUM_CONSUMERS-1:0];
    input [`DATA_BITS-1:0] controller_write_data [`NUM_CONSUMERS-1:0];
    
    // Expected Consumer Outputs
    input [`NUM_CONSUMERS-1:0] expected_consumer_read_ready;
    input [`DATA_BITS-1:0] expected_consumer_read_data [`NUM_CONSUMERS-1:0];
    input [`NUM_CONSUMERS-1:0] expected_consumer_write_ready;
    // Expected Controller Outputs
    input [`NUM_CONSUMERS-1:0] expected_controller_read_valid;
    input [`ADDR_BITS-1:0] expected_controller_read_address [`NUM_CONSUMERS-1:0];
    input [`NUM_CONSUMERS-1:0] expected_controller_write_valid;
    input [`ADDR_BITS-1:0] expected_controller_write_address [`NUM_CONSUMERS-1:0];
    input [`DATA_BITS-1:0] expected_controller_write_data [`NUM_CONSUMERS-1:0];

    output failed;

    begin
        failed = 0;
        `compare_expected(consumer_read_ready, "consumer_read_ready")
        `compare_expected(consumer_read_data,"consumer_read_data")
        `compare_expected(consumer_write_ready,"consumer_write_ready")
        `compare_expected(controller_read_valid,"controller_read_valid")
        `compare_expected(controller_read_address,"controller_read_address")
        `compare_expected(controller_write_valid,"controller_write_valid")
        `compare_expected(controller_write_address,"controller_write_address")
        `compare_expected(controller_write_data,"controller_write_data")
    end
endtask

interface dcache_input_if #(
    parameter ADDR_BITS = `ADDR_BITS,
    parameter DATA_BITS = `DATA_BITS,
    parameter NUM_CONSUMERS = `NUM_CONSUMERS,
    parameter NUM_CHANNELS = `NUM_CHANNELS,
    parameter NUM_BLOCKS = `NUM_BLOCKS,
    parameter NUM_BANKS = `NUM_BANKS,
    parameter NUM_WAYS = `NUM_WAYS,
    parameter CACHE_BLOCK_SIZE = `CACHE_BLOCK_SIZE,
) (input clk);
    logic reset;
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
endinterface

interface dcache_output_if #(
    parameter ADDR_BITS = `ADDR_BITS,
    parameter DATA_BITS = `DATA_BITS,
    parameter NUM_CONSUMERS = `NUM_CONSUMERS,
    parameter NUM_CHANNELS = `NUM_CHANNELS,
    parameter NUM_BLOCKS = `NUM_BLOCKS,
    parameter NUM_BANKS = `NUM_BANKS,
    parameter NUM_WAYS = `NUM_WAYS,
    parameter CACHE_BLOCK_SIZE = `CACHE_BLOCK_SIZE,
) (input clk);
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