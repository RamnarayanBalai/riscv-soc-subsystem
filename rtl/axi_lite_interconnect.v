module axi_lite_interconnect (
  input clk, input reset,
  // Master port (Bridge)
  input [31:0] m_axi_awaddr, input m_axi_awvalid, output m_axi_awready,
  input [31:0] m_axi_wdata, input [3:0] m_axi_wstrb, input m_axi_wvalid, output m_axi_wready,
  output [1:0] m_axi_bresp, output m_axi_bvalid, input m_axi_bready,
  input [31:0] m_axi_araddr, input m_axi_arvalid, output m_axi_arready,
  output [31:0] m_axi_rdata, output [1:0] m_axi_rresp, output m_axi_rvalid, input m_axi_rready,

  // Slave 0 (ROM)
  output [31:0] s0_axi_awaddr, output s0_axi_awvalid, input s0_axi_awready,
  output [31:0] s0_axi_wdata, output [3:0] s0_axi_wstrb, output s0_axi_wvalid, input s0_axi_wready,
  input [1:0] s0_axi_bresp, input s0_axi_bvalid, output s0_axi_bready,
  output [31:0] s0_axi_araddr, output s0_axi_arvalid, input s0_axi_arready,
  input [31:0] s0_axi_rdata, input [1:0] s0_axi_rresp, input s0_axi_rvalid, output s0_axi_rready,

  // Slave 1 (SRAM)
  output [31:0] s1_axi_awaddr, output s1_axi_awvalid, input s1_axi_awready,
  output [31:0] s1_axi_wdata, output [3:0] s1_axi_wstrb, output s1_axi_wvalid, input s1_axi_wready,
  input [1:0] s1_axi_bresp, input s1_axi_bvalid, output s1_axi_bready,
  output [31:0] s1_axi_araddr, output s1_axi_arvalid, input s1_axi_arready,
  input [31:0] s1_axi_rdata, input [1:0] s1_axi_rresp, input s1_axi_rvalid, output s1_axi_rready,

  // Slave 2 (UART)
  output [31:0] s2_axi_awaddr, output s2_axi_awvalid, input s2_axi_awready,
  output [31:0] s2_axi_wdata, output [3:0] s2_axi_wstrb, output s2_axi_wvalid, input s2_axi_wready,
  input [1:0] s2_axi_bresp, input s2_axi_bvalid, output s2_axi_bready,
  output [31:0] s2_axi_araddr, output s2_axi_arvalid, input s2_axi_arready,
  input [31:0] s2_axi_rdata, input [1:0] s2_axi_rresp, input s2_axi_rvalid, output s2_axi_rready
);

  wire [2:0] wr_sel, rd_sel;
  reg  [2:0] wr_sel_r, rd_sel_r;
  reg  wr_active, rd_active;

  axi_decoder wr_dec (.addr(m_axi_awaddr), .sel(wr_sel));
  axi_decoder rd_dec (.addr(m_axi_araddr), .sel(rd_sel));

  always @(posedge clk) begin
    if (reset) begin
      wr_active <= 0; rd_active <= 0;
      wr_sel_r <= 0; rd_sel_r <= 0;
    end else begin
      if (!wr_active && m_axi_awvalid) begin
        wr_active <= 1; wr_sel_r <= wr_sel;
      end else if (m_axi_bvalid && m_axi_bready) begin
        wr_active <= 0;
      end
      if (!rd_active && m_axi_arvalid) begin
        rd_active <= 1; rd_sel_r <= rd_sel;
      end else if (m_axi_rvalid && m_axi_rready) begin
        rd_active <= 0;
      end
    end
  end

  // Write Address Channel
  assign s0_axi_awaddr = m_axi_awaddr; assign s0_axi_awvalid = m_axi_awvalid & wr_sel[0];
  assign s1_axi_awaddr = m_axi_awaddr; assign s1_axi_awvalid = m_axi_awvalid & wr_sel[1];
  assign s2_axi_awaddr = m_axi_awaddr; assign s2_axi_awvalid = m_axi_awvalid & wr_sel[2];
  assign m_axi_awready = (wr_sel[0] & s0_axi_awready) | (wr_sel[1] & s1_axi_awready) | (wr_sel[2] & s2_axi_awready);

  // Write Data Channel
  wire [2:0] act_wr_sel = wr_active ? wr_sel_r : wr_sel;
  assign s0_axi_wdata = m_axi_wdata; assign s0_axi_wstrb = m_axi_wstrb; assign s0_axi_wvalid = m_axi_wvalid & act_wr_sel[0];
  assign s1_axi_wdata = m_axi_wdata; assign s1_axi_wstrb = m_axi_wstrb; assign s1_axi_wvalid = m_axi_wvalid & act_wr_sel[1];
  assign s2_axi_wdata = m_axi_wdata; assign s2_axi_wstrb = m_axi_wstrb; assign s2_axi_wvalid = m_axi_wvalid & act_wr_sel[2];
  assign m_axi_wready = (act_wr_sel[0] & s0_axi_wready) | (act_wr_sel[1] & s1_axi_wready) | (act_wr_sel[2] & s2_axi_wready);

  // Write Response Channel
  assign s0_axi_bready = m_axi_bready & act_wr_sel[0];
  assign s1_axi_bready = m_axi_bready & act_wr_sel[1];
  assign s2_axi_bready = m_axi_bready & act_wr_sel[2];
  assign m_axi_bvalid = (act_wr_sel[0] & s0_axi_bvalid) | (act_wr_sel[1] & s1_axi_bvalid) | (act_wr_sel[2] & s2_axi_bvalid);
  assign m_axi_bresp = (act_wr_sel[0] ? s0_axi_bresp : (act_wr_sel[1] ? s1_axi_bresp : s2_axi_bresp));

  // Read Address Channel
  assign s0_axi_araddr = m_axi_araddr; assign s0_axi_arvalid = m_axi_arvalid & rd_sel[0];
  assign s1_axi_araddr = m_axi_araddr; assign s1_axi_arvalid = m_axi_arvalid & rd_sel[1];
  assign s2_axi_araddr = m_axi_araddr; assign s2_axi_arvalid = m_axi_arvalid & rd_sel[2];
  assign m_axi_arready = (rd_sel[0] & s0_axi_arready) | (rd_sel[1] & s1_axi_arready) | (rd_sel[2] & s2_axi_arready);

  // Read Data Channel
  wire [2:0] act_rd_sel = rd_active ? rd_sel_r : rd_sel;
  assign s0_axi_rready = m_axi_rready & act_rd_sel[0];
  assign s1_axi_rready = m_axi_rready & act_rd_sel[1];
  assign s2_axi_rready = m_axi_rready & act_rd_sel[2];
  assign m_axi_rvalid = (act_rd_sel[0] & s0_axi_rvalid) | (act_rd_sel[1] & s1_axi_rvalid) | (act_rd_sel[2] & s2_axi_rvalid);
  assign m_axi_rdata = (act_rd_sel[0] ? s0_axi_rdata : (act_rd_sel[1] ? s1_axi_rdata : s2_axi_rdata));
  assign m_axi_rresp = (act_rd_sel[0] ? s0_axi_rresp : (act_rd_sel[1] ? s1_axi_rresp : s2_axi_rresp));
endmodule
