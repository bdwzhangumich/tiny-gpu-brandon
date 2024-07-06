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
    output reg [NUM_CONSUMERS-1:0] controller_read_valid,
    output reg [ADDR_BITS-1:0] controller_read_address [NUM_CONSUMERS-1:0],
    input reg [NUM_CONSUMERS-1:0] controller_read_ready,
    input reg [DATA_BITS-1:0] controller_read_data [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] controller_write_valid,
    output reg [ADDR_BITS-1:0] controller_write_address [NUM_CONSUMERS-1:0],
    output reg [DATA_BITS-1:0] controller_write_data [NUM_CONSUMERS-1:0],
    input reg [NUM_CONSUMERS-1:0] controller_write_ready,
);
// TODO: split this module up into multiple modules? eg separate cache access logic and miss handling logic

    localparam  NUM_SETS_PER_BANK = NUM_BLOCKS/NUM_BANKS/NUM_WAYS,
                TAG_LENGTH = ADDR_BITS-$clog2(NUM_BLOCKS/NUM_WAYS)-$clog2(CACHE_BLOCK_SIZE),
                BANK_INDEX_LENGTH = NUM_BANKS > 1 ? $clog2(NUM_BANKS) : 1,
                SET_INDEX_LENGTH = NUM_SETS_PER_BANK > 1 ? $clog2(NUM_SETS_PER_BANK) : 1,
                WAY_INDEX_LENGTH = NUM_WAYS > 1 ? $clog2(NUM_WAYS) : 1,
                BLOCK_INDEX_LENGTH = CACHE_BLOCK_SIZE > 1 ? $clog2(CACHE_BLOCK_SIZE) : 1
                ;

    initial begin
        assert(NUM_WAYS <= NUM_BLOCKS/NUM_BANKS); // this design requires each set fits inside a bank
    end

    // cache state
    // each set is confined to one bank
    reg valids [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    reg dirtys [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    reg mrus [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0]; // bit-plru https://en.wikipedia.org/wiki/Pseudo-LRU
    reg [TAG_LENGTH-1:0] tag_array [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    reg [CACHE_BLOCK_SIZE*8-1:0] banks [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];

    logic next_valids [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    logic next_dirtys [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    logic next_mrus [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    logic [TAG_LENGTH-1:0] next_tag_array [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    logic [CACHE_BLOCK_SIZE*8-1:0] next_banks [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0];
    logic modified [NUM_BANKS-1:0][NUM_SETS_PER_BANK-1:0][NUM_WAYS-1:0]; // whether the entry was modified this cycle

    // indexes
    wire [ADDR_BITS-TAG_LENGTH-1:0] address_after_tag [NUM_CONSUMERS-1:0];
    wire [BANK_INDEX_LENGTH-1:0] bank_indexes [NUM_CONSUMERS-1:0];
    wire [SET_INDEX_LENGTH-1:0] set_indexes [NUM_CONSUMERS-1:0];
    wire [BLOCK_INDEX_LENGTH-1:0] block_offset [NUM_CONSUMERS-1:0];

    // tag search
    wire [TAG_LENGTH-1:0] tags [NUM_CONSUMERS-1:0];
    wire [NUM_WAYS-1:0] tag_hits [NUM_CONSUMERS-1:0]; // bits for which ways are hits

    // bank access
    logic [WAY_INDEX_LENGTH-1:0] hit_way [NUM_CONSUMERS-1:0]; // decoded form of tag_hits
    logic [DATA_BITS-1:0] hit_data [NUM_CONSUMERS-1:0]; // data from cache hit, or data to be written to cache hit

    // cache miss
    // only need stuff for response because, on miss, stuff is just forwarded to controller
    logic [NUM_CONSUMERS-1:0] next_controller_read_valid;
    logic [ADDR_BITS-1:0] next_controller_read_address [NUM_CONSUMERS-1:0];
    logic [NUM_CONSUMERS-1:0] next_controller_write_valid;
    logic [ADDR_BITS-1:0] next_controller_write_address [NUM_CONSUMERS-1:0];
    logic [DATA_BITS-1:0] next_controller_write_data [NUM_CONSUMERS-1:0];

    for (genvar i = 0; i < NUM_CONSUMERS; i++) begin
        assign address_after_tag[i] = ({ADDR_BITS{consumer_read_valid[i]}} & consumer_read_address[i]) | ({ADDR_BITS{consumer_write_valid[i]}} & consumer_write_address[i]);
        assign bank_indexes[i] = NUM_BANKS > 1 ? address_after_tag[i][ADDR_BITS-TAG_LENGTH-1 -: $clog2(NUM_BANKS)] : 0;
        assign set_indexes[i] = NUM_SETS_PER_BANK > 1 ? address_after_tag[i][$clog2(CACHE_BLOCK_SIZE) +: SET_INDEX_LENGTH] : 0;
        assign block_offset[i] = CACHE_BLOCK_SIZE > 1 ? address_after_tag[i] : 0;
    end

    for (genvar i = 0; i < NUM_CONSUMERS; i++) begin
        assign tags[i] = (({ADDR_BITS{consumer_read_valid[i]}} & consumer_read_address[i]) | ({ADDR_BITS{consumer_write_valid[i]}} & consumer_write_address[i])) >> (ADDR_BITS - TAG_LENGTH);
        for (genvar j = 0; j < NUM_WAYS; j++) begin
            assign tag_hits[i][j] = valids[bank_indexes[i]][set_indexes[i]][j] && tags[i] == tag_array[bank_indexes[i]][set_indexes[i]][j];
        end
    end

    always_comb begin : bank_read
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

    always_comb begin : bank_write
        next_valids = valids;
        next_dirtys = dirtys;
        next_tag_array = tag_array;
        next_banks = banks;
        next_mrus = mrus;

        next_controller_read_valid = 0;
        next_controller_read_address = 0;
        next_controller_write_valid = controller_write_valid;
        next_controller_write_address = controller_write_address;
        next_controller_write_data = controller_write_data;
        for (int i = 0; i < NUM_CONSUMERS; i++) begin
            // dont do anything if still waiting for past eviction to finish
            if (!controller_write_valid[i] || controller_write_ready[i]) begin
                next_controller_read_valid[i] = !consumer_read_ready[i] && !|tag_hits[i] && (consumer_read_valid[i] || consumer_read_address[i]);
                next_controller_read_address[i] = ({ADDR_BITS{consumer_read_valid[i]}} & consumer_read_address[i]) | ({ADDR_BITS{consumer_write_valid[i]}} & consumer_write_address[i]);
                // stop any past evictions
                next_controller_write_valid[i] = 0;
                next_controller_write_address[i] = 0;
                next_controller_write_data[i] = 0;
            end
        end

        // store hit
        for (int i = 0; i < NUM_CONSUMERS; i++) begin 
            if (consumer_write_valid[i] && |tag_hits[i]) begin
                next_banks[bank_indexes[i]][set_indexes[i]][hit_way[i]][8*block_offset[i] +: 8] = hit_data[i];
                next_dirtys[bank_indexes[i]][set_indexes[i]][hit_way[i]] = 1;
                next_mrus[bank_indexes[i]][set_indexes[i]][hit_way[i]] = 1;
                modified[bank_indexes[i]][set_indexes[i]][hit_way[i]] = 1;
            end
        end
        // clear mrus if all 1s
        for (int i = 0; i < NUM_BANKS; i++)
            for (int j = 0; j < NUM_SETS_PER_BANK; j++)
                if (&next_mrus[i][j]) next_mrus[i][j] = 0;
        // write data from memory controller
        for (int i = 0; i < NUM_CONSUMERS; i++) begin 
            if ((consumer_read_valid[i] | consumer_write_valid[i]) && controller_read_ready[i]) begin // check if lsu is requesting and controller is ready
                if (&next_valids[bank_indexes[i]][set_indexes[i]]) begin
                    // eviction
                    for (int j = 0; j < NUM_WAYS; j++) begin
                        if (!modified[bank_indexes[i]][set_indexes[i]][j] && !next_mrus[bank_indexes[i]][set_indexes[i]][j]) begin
                            next_valids[bank_indexes[i]][set_indexes[i]][j] = 0;
                            modified[bank_indexes[i]][set_indexes[i]][j] = 1;
                            if (next_dirtys[bank_indexes[i]][set_indexes[i]][j]) begin
                                next_dirtys[bank_indexes[i]][set_indexes[i]][j] = 0;
                                // write back to memory
                                next_controller_write_valid[i] = 1;
                                next_controller_write_address[i] = {next_tag_array[bank_indexes[i]][set_indexes[i]][j], bank_indexes[i], set_indexes[i], {$clog2(CACHE_BLOCK_SIZE){1'b0}}};
                                next_controller_write_data[i] = next_banks[bank_indexes[i]][set_indexes[i]][j];
                                next_controller_read_valid[i] = 0; // prevent reading and writing at same time on same interface
                            end
                            break;
                        end
                    end
                end
                // write to open block, or do nothing if no blocks could be evicted and set is still full
                for (int j = 0; j < NUM_WAYS; j++) begin
                    if (!next_valids[bank_indexes[i]][set_indexes[i]][j]) begin
                        next_valids[bank_indexes[i]][set_indexes[i]][j] = 1;
                        next_mrus[bank_indexes[i]][set_indexes[i]][j] = 1;
                        next_tag_array[bank_indexes[i]][set_indexes[i]][j] = (({ADDR_BITS{consumer_read_valid[i]}} & consumer_read_address[i]) | ({ADDR_BITS{consumer_write_valid[i]}} & consumer_write_address[i])) >> (ADDR_BITS - TAG_LENGTH);
                        next_banks[bank_indexes[i]][set_indexes[i]][j] = controller_read_data[i];
                        if (consumer_write_valid[i]) begin
                            // write new data from lsu
                            next_banks[bank_indexes[i]][set_indexes[i]][j][8*block_offset[i] +: 8] = consumer_write_data[i];
                            next_dirtys[bank_indexes[i]][set_indexes[i]][j] = 1;
                        end
                        next_controller_read_valid[i] = 0;
                        break;
                    end
                end
            end
        end
        // clear mrus if all 1s
        for (int i = 0; i < NUM_BANKS; i++)
            for (int j = 0; j < NUM_SETS_PER_BANK; j++)
                if (&next_mrus[i][j]) next_mrus[i][j] = 0;
    end

    always @(posedge clk) begin
        if (reset) begin 
            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;

            controller_read_valid <= 0;
            controller_read_address <= 0;
            controller_write_valid <= 0;
            controller_write_address <= 0;
            controller_write_data <= 0;

            valids <= 0;
            dirtys <= 0;
            mrus <= 0;
            tag_array <= 0;
            banks <= 0;

        end else begin 
            valids <= next_valids;
            dirtys <= next_dirtys;
            mrus <= next_mrus;
            tag_array <= next_tag_array;
            banks <= next_banks;

            controller_read_valid <= next_controller_read_valid;
            controller_read_address <= next_controller_read_address;
            controller_write_valid <= next_controller_write_valid;
            controller_write_address <= next_controller_write_address;
            controller_write_data <= next_controller_write_data;

            for (int i = 0; i < NUM_CONSUMERS; i++) begin 
                if (consumer_read_valid[i] && |tag_hits[i]) begin 
                    consumer_read_ready[i] <= 1;
                    consumer_read_data[i] <= hit_data[i];
                end
                else if (consumer_write_valid[i] && |tag_hits[i]) begin 
                    consumer_write_ready[i] <= 1;
                end
                else begin
                    consumer_read_ready[i] <= 0;
                    consumer_write_ready[i] <= 0;
                end
            end
        end
    end
endmodule
