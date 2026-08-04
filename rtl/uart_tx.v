module uart_tx (
  input clk, input rst_n, input tx_en, input [7:0] tx_data,
  output reg tx_out, output reg tx_busy
);
  localparam CLKS_PER_BIT = 434;
  reg [1:0] state;
  reg [8:0] count;
  reg [2:0] bit_idx;
  reg [7:0] data;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= 0; count <= 0; bit_idx <= 0; data <= 0;
      tx_out <= 1; tx_busy <= 0;
    end else begin
      case (state)
        0: begin // IDLE
          tx_out <= 1; tx_busy <= 0; count <= 0; bit_idx <= 0;
          if (tx_en) begin
            data <= tx_data; state <= 1; tx_busy <= 1;
          end
        end
        1: begin // START
          tx_out <= 0;
          if (count == CLKS_PER_BIT-1) begin
            count <= 0; state <= 2;
          end else count <= count + 1;
        end
        2: begin // DATA
          tx_out <= data[bit_idx];
          if (count == CLKS_PER_BIT-1) begin
            count <= 0;
            if (bit_idx == 7) state <= 3; else bit_idx <= bit_idx + 1;
          end else count <= count + 1;
        end
        3: begin // STOP
          tx_out <= 1;
          if (count == CLKS_PER_BIT-1) begin
            count <= 0; state <= 0;
          end else count <= count + 1;
        end
      endcase
    end
  end
endmodule
