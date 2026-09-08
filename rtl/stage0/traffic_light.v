// Stage 0 exercise — traffic light FSM + datapath
// RED (4 cyc) -> GREEN (3 cyc) -> YELLOW (1 cyc) -> RED ...
// Moore FSM: outputs depend only on current state.

module traffic_light (
    input  wire clk,
    input  wire rst_n,     // active-low synchronous reset
    output wire red,
    output wire yellow,
    output wire green
);

    // state encoding
    localparam [1:0] S_RED    = 2'd0,
                      S_GREEN  = 2'd1,
                      S_YELLOW = 2'd2;

    // per-state cycle counts (datapath limits)
    localparam [2:0] RED_LIMIT    = 3'd4,
                      GREEN_LIMIT  = 3'd3,
                      YELLOW_LIMIT = 3'd1;

    reg [1:0] state, next_state;
    reg [2:0] count;          // datapath: cycles spent in current state
    reg       count_reset;    // control signal into datapath
    reg       red_r, green_r, yellow_r;  // retimed output regs

    // datapath: counter register
    always @(posedge clk) begin
        if (!rst_n)
            count <= 3'd0;
        else if (count_reset)
            count <= 3'd0;
        else
            count <= count + 3'd1;
    end

    // state register
    always @(posedge clk) begin
        if (!rst_n)
            state <= S_RED;
        else
            state <= next_state;
    end

    // retimed output register — decode moved ahead of the flop (off next_state,
    // not state), so red/green/yellow drive straight off a flop with zero
    // combinational gates after it. Functionally identical to the old
    // `assign red = (state == S_RED)`, since state <= next_state on the same
    // edge; only the position of the decode logic relative to the register
    // changed. This was the fix for the -0.56ns setup violation on `red`.
    always @(posedge clk) begin
        if (!rst_n) begin
            red_r    <= 1'b1;   // matches state's reset value S_RED
            green_r  <= 1'b0;
            yellow_r <= 1'b0;
        end else begin
            red_r    <= (next_state == S_RED);
            green_r  <= (next_state == S_GREEN);
            yellow_r <= (next_state == S_YELLOW);
        end
    end

    // next-state + count_reset logic (combinational)
    always @(*) begin
        next_state  = state;
        count_reset = 1'b0;
        case (state)
            S_RED: begin
                if (count == RED_LIMIT - 1'b1) begin
                    next_state  = S_GREEN;
                    count_reset = 1'b1;
                end
            end
            S_GREEN: begin
                if (count == GREEN_LIMIT - 1'b1) begin
                    next_state  = S_YELLOW;
                    count_reset = 1'b1;
                end
            end
            S_YELLOW: begin
                if (count == YELLOW_LIMIT - 1'b1) begin
                    next_state  = S_RED;
                    count_reset = 1'b1;
                end
            end
            default: next_state = S_RED;
        endcase
    end

    // output logic (Moore — depends only on state, now registered directly)
    assign red    = red_r;
    assign green  = green_r;
    assign yellow = yellow_r;

endmodule
