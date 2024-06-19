`default_nettype none
`timescale 1ns/1ns

module dcache #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 8,
    parameter NUM_CONSUMERS = 8, // The number of consumers accessing memory through this controller
    parameter NUM_CHANNELS = 8,  // The number of concurrent channels available to send requests to controller
    parameter NUM_BLOCKS = 2, // The number of blocks in the cache
    parameter NUM_BANKS = 2, // The number of banks in the cache
    parameter NUM_WAYS = 1, // The associativity of the cache
    parameter CACHE_BLOCK_SIZE = 1, // The number of bytes each cache block should be
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

    // Controller Interface
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

    localparam  NUM_SETS_PER_BANK = NUM_BLOCKS/NUM_BANKS/NUM_WAYS,
                TAG_LENGTH = ADDR_BITS-$clog2(NUM_BLOCKS/NUM_WAYS)-$clog2(CACHE_BLOCK_SIZE),
                BANK_INDEX_LENGTH = NUM_BANKS > 1 ? clog2(NUM_BANKS) : 1,
                SET_INDEX_LENGTH = NUM_SETS_PER_BANK > 1 ? clog2(NUM_SETS_PER_BANK) : 1,
                BLOCK_INDEX_LENGTH = CACHE_BLOCK_SIZE > 1 ? clog2(CACHE_BLOCK_SIZE) : 1
                ;

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
    wire [BANK_INDEX_LENGTH-1:0] bank_indexes [NUM_CONSUMERS-1:0];
    wire [SET_INDEX_LENGTH-1:0] set_indexes [NUM_CONSUMERS-1:0];
    wire [BLOCK_INDEX_LENGTH-1:0] block_offset [NUM_CONSUMERS-1:0];

    // tag search
    wire [TAG_LENGTH-1:0] tags [NUM_CONSUMERS-1:0];
    wire tag_hits [NUM_CONSUMERS-1:0][NUM_WAYS-1:0]; // bits for which ways are hits

    // bank access
    logic [$clog2(NUM_WAYS)] hit_way [NUM_CONSUMERS-1:0]; // decoded form of tag_hits
    logic [DATA_BITS-1:0] hit_data [NUM_CONSUMERS-1:0]; // data from cache hit, or data to be written to cache hit

    // cache miss
    // only need stuff for response because, on miss, stuff is just forwarded to controller


    for (genvar i = 0; i < NUM_CONSUMERS; i++) begin
        assign address_after_tag[i] = (consumer_read_valid[i] & consumer_read_address[i]) | (consumer_write_valid[i] & consumer_write_address[i]);
        assign bank_indexes[i] = NUM_BANKS > 1 ? address_after_tag[i][ADDR_BITS-TAG_LENGTH-1 -: $clog2(NUM_BANKS)] : 0;
        assign set_indexes[i] = NUM_SETS_PER_BANK > 1 ? address_after_tag[i][$clog2(CACHE_BLOCK_SIZE) +: $clog(NUM_SETS_PER_BANK)] : 0;
        assign block_offset[i] = CACHE_BLOCK_SIZE > 1 ? address_after_tag[i] : 0;
    end

    for (genvar i = 0; i < NUM_CONSUMERS; i++) begin
        assign tags[i] = ((consumer_read_valid[i] & consumer_read_address[i]) | (consumer_write_valid[i] & consumer_write_address[i]))[ADDR_BITS-1:ADDR_BITS-TAG_LENGTH];
        for (genvar j = 0; j < NUM_WAYS; j++) begin
            assign tag_hits[i][j] = valids[bank_indexes][set_indexes[i]][j] && tags[i] == tag_array[bank_indexes[i]][set_indexes[i]][j];
        end
    end

    always_comb begin : bank_access
        hit_way = 0;
        hit_data = 0;
        for (int i = 0; i < NUM_CONSUMERS; i++) begin
            for (int j = 0; j < NUM_WAYS; j++) begin
                if (tag_hits[i][j]) begin
                    hit_way |= j;
                end
            end
        end
        for (int i = 0; i < NUM_CONSUMERS; i++) begin
            if (consumer_read_valid[i]) begin
                hit_data[i] = banks[bank_indexes[i]][set_indexes[i]][hit_way[i]][8*block_offset[i] +: 8];
            end
            else if (consumer_write_valid[i]) begin
                hit_data[i] = consumer_write_data[i];
            end
        end
    end

    // TODO: handle cache miss by forwarding request to dcontroller
    // need to deal with eviction and write to same block on same cycle, probably by arbitrating with a next_blocks array and delaying eviction

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

            valids <= 0;
            dirtys <= 0;
            tag_array <= 0;
            banks <= 0;

        end else begin 
            for (int i = 0; i < NUM_CONSUMERS; i++) begin 
                if (consumer_read_valid[i] && |tag_hits[i]) begin 
                    consumer_read_ready[i] <= 1;
                    consumer_read_data[i] <= hit_data[i];
                end
                else if (consumer_write_valid[i] && |tag_hits[i]) begin 
                    consumer_write_ready[i] <= 1;
                    banks[bank_indexes[i]][set_indexes[i]][hit_way[i]][8*block_offset[i] +: 8] <= hit_data[i];
                    dirtys[bank_indexes[i]][set_indexes[i]][hit_way[i]] <= 1;
                end
                else begin
                    consumer_read_ready[i] <= 0;
                    consumer_write_ready[i] <= 0;

                    controller_read_valid[i] <= consumer_read_valid[i];
                    controller_read_address[i] <= consumer_read_address[i];
                    controller_write_valid[i] <= consumer_write_valid[i];
                    controller_write_address[i] <= consumer_write_address[i];
                    controller_write_data[i] <= consumer_write_data[i];
                end
            end
        end
    end
endmodule
