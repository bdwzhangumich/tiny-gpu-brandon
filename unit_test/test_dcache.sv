`timescale 1ns/1ns

`define ADDR_BITS 8
`define DATA_BITS 8
`define NUM_CONSUMERS 8
`define NUM_CHANNELS 8
`define NUM_BLOCKS 8
`define NUM_BANKS 2
`define NUM_WAYS 4
`define CACHE_BLOCK_SIZE 1

`define HALF_CYCLE_LENGTH 5

`define RANDOM_TEST_CYCLES 1000

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
    
    // arrays for tracking what is in cache in random tests
    reg [NUM_BLOCKS-1:0] valids;
    reg [NUM_BLOCKS-1:0] addresses [ADDR_BITS-1:0];
    reg [NUM_BLOCKS-1:0] data [DATA_BITS-1:0];

    always #`HALF_CYCLE_LENGTH clk =~ clk;
    
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
        $dumpfile("sim/dcache.vcd");
        $dumpvars(2,data_cache);
        clk = 0;
        failed = 0;

        // Manual Test 0
        // Tests one load and one store
        $display("Manual test 0 begin at Cycle %0t", $time/2/`HALF_CYCLE_LENGTH);
        fork
            manual_test0_driver();
            manual_test0_scoreboard();
        join
        $display("Manual test 0 completed");

        // Manual Test 1
        // Tests a load, store, and load in sequence and all to the same address
        $display("Manual test 1 begin at Cycle %0t", $time/2/`HALF_CYCLE_LENGTH);
        fork
            manual_test1_driver();
            manual_test1_scoreboard();
        join
        $display("Manual test 1 end");

        // TODO: in manual scoreboards, have compare_output_interfaces run in a separate always block
        // instead of manually at every negedge

        // TODO: add tests where many consumers request at the same time
        // one test with multiple consumers targeting the same addresses
        // one test with multiple consumer targeting different blocks in the same set and filling up the set
        // combinations of the above tests using stores instead of loads
        
        // TODO: create random tests
        // randomly generate requests, give the cache random data from controller
        // store data given to controller and compare against controller outputs
        // check that all requests are eventually serviced and that the cache evicts something when it is full
        // have one test with one requester at a time, then more tests with more requesters

        // TODO: add asserts
        // dcache does not request controller reads and writes at the same time
        // dcache does not output read and write ready bits at same time

        // TODO: use asserts instead of $display?

        // Random Test 0
        // Continuously request random loads through one consumer and provide random data through controller
        $display("Random test 0 begin at Cycle %0t", $time/2/`HALF_CYCLE_LENGTH);
        fork
            random_test0_driver();
            random_test0_scoreboard();
        join
        $display("Random test 0 end");

        if (failed === 0)
            $display("Passed!");
        else
            $display("Failed!");
        $finish;
    end

    task manual_test0_driver;
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
            in_if.consumer_read_address[0] = 'hFF; // TODO: look into why commenting this line changes read_data
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
    endtask

    task manual_test0_scoreboard;
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
            compare_output_interfaces();
            @(negedge clk); // Cycle 2
            // dcache forwards load and store to memory controller
            expected_out_if.controller_read_valid[0] = 1;
            expected_out_if.controller_read_address[0] = 'hFF;
            expected_out_if.controller_read_valid[1] = 1;
            expected_out_if.controller_read_address[1] = 'hF0;
            compare_output_interfaces();
            @(negedge clk); // Cycle 3
            // dcache copies data to banks and gives ack to memory controller
            expected_out_if.controller_read_valid[1:0] = 0;
            expected_out_if.controller_read_address[0] = 0;
            expected_out_if.controller_read_address[1] = 0;
            compare_output_interfaces();
            @(negedge clk); // Cycle 4
            // dcache responds to load and store from consumers
            expected_out_if.consumer_read_ready[0] = 1;
            expected_out_if.consumer_read_data[0] = 'hFF;
            expected_out_if.consumer_write_ready[1] = 1;
            compare_output_interfaces();
        end
    endtask

    task manual_test1_driver;
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
            @(negedge clk); // Cycle 2
            // give dcache data from memory controller
            in_if.controller_read_ready[0] = 1;
            in_if.controller_read_data[0] = 'hFF;
            @(negedge clk); // Cycle 3
            @(negedge clk); // Cycle 4
            // memory controller stops driving in response to acks
            in_if.controller_read_ready[0] = 0;
            in_if.controller_read_data[0] = 0;
            @(negedge clk); // Cycle 5
            // consumer stops driving in response to cache response
            in_if.consumer_read_valid[0] = 0;
            // request store from dcache
            in_if.consumer_write_valid[1] = 1;
            in_if.consumer_write_address[1] = 'hFF;
            in_if.consumer_write_data[1] = 'hF0;
            @(negedge clk); // Cycle 6
            // consumer stops driving in response to cache response
            in_if.consumer_write_valid[1] = 0;
            // request load from dcache
            in_if.consumer_read_valid[0] = 1;
            @(negedge clk); // Cycle 7
            // consumer stops driving in response to cache response
            in_if.consumer_read_valid[0] = 0;
        end
    endtask

    task manual_test1_scoreboard;
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
            compare_output_interfaces();
            @(negedge clk); // Cycle 2
            // dcache forwards load to memory controller
            expected_out_if.controller_read_valid[0] = 1;
            expected_out_if.controller_read_address[0] = 'hFF;
            compare_output_interfaces();
            @(negedge clk); // Cycle 3
            // dcache copies data to banks and gives ack to memory controller
            expected_out_if.controller_read_valid[0] = 0;
            expected_out_if.controller_read_address[0] = 0;
            compare_output_interfaces();
            @(negedge clk); // Cycle 4
            // dcache responds to load from consumer
            expected_out_if.consumer_read_ready[0] = 1;
            expected_out_if.consumer_read_data[0] = 'hFF;
            compare_output_interfaces();
            @(negedge clk); // Cycle 5
            compare_output_interfaces();
            @(negedge clk); // Cycle 6
            // dcache stops driving in response to consumer ack
            expected_out_if.consumer_read_ready[0] = 0;
            // dcache responds to store from consumer
            expected_out_if.consumer_write_ready[1] = 1;
            compare_output_interfaces();
            @(negedge clk); // Cycle 7
            // dcache stops driving in response to consumer ack
            expected_out_if.consumer_write_ready[1] = 0;
            // dcache responds to load from consumer
            expected_out_if.consumer_read_ready[0] = 1;
            expected_out_if.consumer_read_data[0] = 'hF0;
            compare_output_interfaces();
            @(negedge clk); // Cycle 8
            // dcache stops driving in response to consumer ack
            expected_out_if.consumer_read_ready[0] = 0;
            compare_output_interfaces();
        end
    endtask

    task random_test0_driver;
        begin
            valids = 0;
            addresses = 0;
            data = 0;

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

            for(int i = 0; i < `RANDOM_TEST_CYCLES; i++) begin
                if (!in_if.consumer_read_valid[0] && !out_if.consumer_read_ready[0]) begin
                    // generate new request
                    in_if.consumer_read_valid[0] = 1;
                    // either request an address that is currently in the cache or a new address
                    if (|valids && $random()) begin
                        int block = $urandom() % NUM_BLOCKS;
                        in_if.consumer_read_address[0] = addresses[block];
                    end
                    else begin
                        in_if.consumer_read_address[0] = $random();
                    end
                end
                if (out_if.controller_write_valid[0] && !in_if.controller_write_ready[0]) begin
                    // remove block
                    for(int i = 0; i < NUM_BLOCKS; i++) begin
                        if(addresses[i] == out_if.controller_write_address[0])
                            valids[i] = 0;
                    end
                    in_if.in_if.controller_write_ready[0] = 1; // ack
                end
                if (!out_if.controller_write_valid[0] && in_if.controller_write_ready[0])
                    in_if.controller_write_ready[0] = 0; // ack
                if (out_if.controller_read_valid[0] && !in_if.controller_read_ready[0]) begin
                    // add new block
                    for(int i = 0; i < NUM_BLOCKS; i++)
                        if(!valids[i]) begin
                            valids[i] = 1;
                            addresses[i] = out_if.controller_read_address[0];
                            data[i] = $random();
                            // give data to cache
                            in_if.controller_read_ready[0] = 1;
                            in_if.controller_read_data[0] = data[i];
                        end
                end
                if (!out_if.controller_read_valid[0] && in_if.controller_read_ready[0])
                    in_if.controller_read_ready[0] = 0; // ack
                if (in_if.consumer_read_valid[0] && out_if.consumer_read_ready[0])
                    in_if.consumer_read_valid[0] = 0; // ack read
                @(negedge clk);
                #1; // prevent race conditions with scoreboard
            end
        end
    endtask
    int consumer_read_timer;
    task random_test0_scoreboard;
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
            compare_output_interfaces();
            @(negedge clk); // Cycle 2

            // TODO: check that controller writes have correct values and addresses
            // TODO: check that controller reads have correct addresses and are only for addresses not in cache

            // TODO: could the cache data checks have race conditions with the driver?
            // if not, remove delay from driver. if delay does not work, figure out why
            consumer_read_timer = 0;
            for(int i = 0; i < `RANDOM_TEST_CYCLES; i++) begin
                if (!out_if.consumer_read_ready[0])
                    consumer_read_timer++;
                if (out_if.consumer_read_ready[0]) begin
                    consumer_read_timer = 0;
                    // TODO: check that consumer responses have correct values and addresses
                    for(int i = 0; i < NUM_BLOCKS; i++ ) begin
                        if(valids[i] && addresses[i] == in_if.consumer_read_address[0]) begin
                            if (data[i] != out_if.consumer_read_data[0]) begin
                                failed = 1;
                                $display("Consumer read gave incorrect data");
                            end
                        end
                        // TODO: do I need to check if address was found?
                    end
                end
                
                if (consumer_read_timer > `RANDOM_TEST_CYCLES / 4) begin
                    failed = 1;
                    $display("Consumer read timed out");
                    break;
                end
                @(negedge clk);
            end
        end
    endtask

    `define compare_expected(port) if (out_if.``port`` !== expected_out_if.``port``) begin \
                $display ( \
                    "Failure at Cycle %0t: %s=0x%0h expected_%s=0x%0h", \
                    $time/2/`HALF_CYCLE_LENGTH, \
                    `"port`", \
                    out_if.``port``, \
                    `"port`", \
                    expected_out_if.``port`` \
                ); \
                failed = 1; \
            end
    task compare_output_interfaces;
        begin
            failed = 0;
            `compare_expected(consumer_read_ready)
            `compare_expected(consumer_read_data)
            `compare_expected(consumer_write_ready)
            `compare_expected(controller_read_valid)
            `compare_expected(controller_read_address)
            `compare_expected(controller_write_valid)
            `compare_expected(controller_write_address)
            `compare_expected(controller_write_data)
        end
    endtask
endmodule

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
