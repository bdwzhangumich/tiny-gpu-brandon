`default_nettype none
`timescale 1ns/1ns

module dcache #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 8,
    parameter NUM_CONSUMERS = 8, // The number of consumers accessing memory through this controller
    parameter NUM_CHANNELS = 8,  // The number of concurrent channels available to send requests to controller
    parameter CACHE_BLOCK_SIZE = 1, // The number of bytes each cache block should be  
    parameter NUM_BLOCKS = 2, // The number of blocks in the cache
    parameter NUM_BANKS = 2, // The number of banks in the cache
    parameter NUM_WAYS = 1, // The associativity of the cache
) (
    input wire clk,
    input wire reset,

    // Consumer Interface (Fetchers / LSUs)
    input reg [NUM_CONSUMERS-1:0] consumer_read_valid,
    input reg [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0],
    input reg [NUM_CONSUMERS-1:0] consumer_write_valid,
    input reg [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0],
    input reg [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // Memory Interface (Data / Program)
    input reg [NUM_CHANNELS-1:0] controller_read_valid,
    input reg [ADDR_BITS-1:0] controller_read_address [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] controller_read_ready,
    output reg [DATA_BITS-1:0] controller_read_data [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] controller_write_valid,
    input reg [ADDR_BITS-1:0] controller_write_address [NUM_CHANNELS-1:0],
    input reg [DATA_BITS-1:0] controller_write_data [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] controller_write_ready,
);
    localparam IDLE = 3'b000, 
        READ_WAITING = 3'b010, 
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    localparam  TAG_LENGTH = ADDR_BITS-$clog2(NUM_BLOCKS/NUM_WAYS)-$clog2(CACHE_BLOCK_SIZE),
                NUM_SETS_PER_BANK = NUM_BLOCKS/NUM_BANKS/NUM_WAYS;

    initial begin
        assert(NUM_WAYS <= NUM_BLOCKS/NUM_BANKS) // this design requires each set fits inside a bank
    end

    // each set is confined to one bank
    reg valids [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    reg dirtys [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    reg [TAG_LENGTH-1:0] tag_array [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    reg [CACHE_BLOCK_SIZE*8-1:0] banks [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    // TODO: eviction logic

    // indexes
    wire [ADDR_BITS-TAG_LENGTH-1:0] address_after_tag [NUM_CONSUMERS-1:0];
    wire [$clog2(NUM_BANKS)-1:0] bank_indexes [NUM_CONSUMERS-1:0];
    wire [$clog2(NUM_SETS_PER_BANK)-1:0] set_indexes [NUM_CONSUMERS-1:0];
    wire [$clog2(NUM_WAYS)-1:0] entry_indexes [NUM_CONSUMERS-1:0];

    // tag search
    wire [TAG_LENGTH-1:0] tags [NUM_CONSUMERS-1:0];
    wire tag_matches [NUM_CONSUMERS-1:0][NUM_WAYS-1:0];

    for (genvar i = 0; i < NUM_CONSUMERS; i++) begin
        assign address_after_tag[i] = (consumer_read_valid[i] & consumer_read_address[i]) | (consumer_write_valid[i] & consumer_write_address[i]);
        assign bank_indexes[i] = address_after_tag[i][ADDR_BITS-TAG_LENGTH-1 -: $clog2(NUM_BANKS)];
        assign set_indexes[i] = address_after_tag[i][$clog2(NUM_WAYS)+$clog2(CACHE_BLOCK_SIZE) +: $clog(NUM_SETS_PER_BANK)];
        assign entry_indexes[i] = address_after_tag[i][$clog2(CACHE_BLOCK_SIZE) +: $clog2(NUM_WAYS)];
    end

    for (genvar i = 0; i < NUM_CONSUMERS; i++) begin
        assign tags[i] = ((consumer_read_valid[i] & consumer_read_address[i]) | (consumer_write_valid[i] & consumer_write_address[i]))[ADDR_BITS-1:ADDR_BITS-TAG_LENGTH];
        for (genvar j = 0; j < NUM_WAYS; j++) begin
            assign tag_matches[i][j] = valids[bank_indexes][set_indexes[i]][j] && tags[i] == tag_array[bank_indexes[i]][set_indexes[i]][j];
        end
    end

    // TODO: return value on match for loads and write value for stores
    // TODO: handle cache miss by forwarding request to dcontroller

    always @(posedge clk) begin
        if (reset) begin 
            mem_read_valid <= 0;
            mem_read_address <= 0;

            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;

            current_consumer <= 0;
            controller_state <= 0;

            channel_serving_consumer = 0;
        end else begin 
            // For each channel, we handle processing concurrently
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin 
                case (controller_state[i])
                    IDLE: begin
                        // While this channel is idle, cycle through consumers looking for one with a pending request
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin 
                            if (consumer_read_valid[j] && !channel_serving_consumer[j]) begin 
                                channel_serving_consumer[j] = 1;
                                current_consumer[i] <= j;

                                mem_read_valid[i] <= 1;
                                mem_read_address[i] <= consumer_read_address[j];
                                controller_state[i] <= READ_WAITING;

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                break;
                            end else if (consumer_write_valid[j] && !channel_serving_consumer[j]) begin 
                                channel_serving_consumer[j] = 1;
                                current_consumer[i] <= j;

                                mem_write_valid[i] <= 1;
                                mem_write_address[i] <= consumer_write_address[j];
                                mem_write_data[i] <= consumer_write_data[j];
                                controller_state[i] <= WRITE_WAITING;

                                // Once we find a pending request, pick it up with this channel and stop looking for requests
                                break;
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Wait for response from memory for pending read request
                        if (mem_read_ready[i]) begin 
                            mem_read_valid[i] <= 0;
                            consumer_read_ready[current_consumer[i]] <= 1;
                            consumer_read_data[current_consumer[i]] <= mem_read_data[i];
                            controller_state[i] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin 
                        // Wait for response from memory for pending write request
                        if (mem_write_ready[i]) begin 
                            mem_write_valid[i] <= 0;
                            consumer_write_ready[current_consumer[i]] <= 1;
                            controller_state[i] <= WRITE_RELAYING;
                        end
                    end
                    // Wait until consumer acknowledges it received response, then reset
                    READ_RELAYING: begin
                        if (!consumer_read_valid[current_consumer[i]]) begin 
                            channel_serving_consumer[current_consumer[i]] = 0;
                            consumer_read_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin 
                        if (!consumer_write_valid[current_consumer[i]]) begin 
                            channel_serving_consumer[current_consumer[i]] = 0;
                            consumer_write_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
