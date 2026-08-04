module top (
  input clk,
  input reset, // Active HIGH from testbench
  output uart_tx,
  input uart_rx
);
  wire resetn = ~reset;

  // CPU native interface
  wire        cpu_mem_valid;
  wire        cpu_mem_instr;
  wire        cpu_mem_ready;
  wire [31:0] cpu_mem_addr;
  wire [31:0] cpu_mem_wdata;
  wire [3:0]  cpu_mem_wstrb;
  wire [31:0] cpu_mem_rdata;

  picorv32 #(
    .ENABLE_MUL(1), .ENABLE_DIV(1), .COMPRESSED_ISA(1),
    .ENABLE_IRQ(0), .PROGADDR_RESET(32'h0000_0000)
  ) u_cpu (
    .clk(clk), .resetn(resetn),
    .mem_valid(cpu_mem_valid), .mem_instr(cpu_mem_instr),
    .mem_ready(cpu_mem_ready), .mem_addr(cpu_mem_addr),
    .mem_wdata(cpu_mem_wdata), .mem_wstrb(cpu_mem_wstrb),
    .mem_rdata(cpu_mem_rdata)
  );

  // AXI Master Signals
  reg [31:0] m_axi_awaddr; reg m_axi_awvalid; wire m_axi_awready;
  reg [31:0] m_axi_wdata;  reg [3:0] m_axi_wstrb_r; reg m_axi_wvalid; wire m_axi_wready;
  wire [1:0] m_axi_bresp; wire m_axi_bvalid; reg m_axi_bready;
  reg [31:0] m_axi_araddr; reg m_axi_arvalid; wire m_axi_arready;
  wire [31:0] m_axi_rdata; wire [1:0] m_axi_rresp; wire m_axi_rvalid; reg m_axi_rready;

  reg [2:0] b_state;
  reg [31:0] rdata_r;
  reg ready_r;

  assign cpu_mem_ready = ready_r;
  assign cpu_mem_rdata = rdata_r;

  // Bridge FSM
  always @(posedge clk) begin
    if (reset) begin
      b_state <= 0; ready_r <= 0; rdata_r <= 0;
      m_axi_awvalid <= 0; m_axi_wvalid <= 0; m_axi_bready <= 0;
      m_axi_arvalid <= 0; m_axi_rready <= 0;
    end else begin
      ready_r <= 0;
      case (b_state)
        0: begin // IDLE
          if (cpu_mem_valid) begin
            if (|cpu_mem_wstrb) begin
              m_axi_awaddr <= cpu_mem_addr; m_axi_awvalid <= 1;
              m_axi_wdata <= cpu_mem_wdata; m_axi_wstrb_r <= cpu_mem_wstrb; m_axi_wvalid <= 1;
              b_state <= 1; // WR_AW
            end else begin
              m_axi_araddr <= cpu_mem_addr; m_axi_arvalid <= 1;
              b_state <= 3; // RD_AR
            end
          end
        end
        1: begin // WR_AW
          if (m_axi_awready) m_axi_awvalid <= 0;
          if (m_axi_wready) m_axi_wvalid <= 0;
          m_axi_bready <= 1;
          if (m_axi_bvalid) begin
            ready_r <= 1; b_state <= 0; m_axi_bready <= 0;
          end else if (!m_axi_awvalid && !m_axi_wvalid) begin
            b_state <= 2; // WR_B
          end
        end
        2: begin // WR_B
          m_axi_bready <= 1;
          if (m_axi_bvalid) begin
            ready_r <= 1; b_state <= 0; m_axi_bready <= 0;
          end
        end
        3: begin // RD_AR
          if (m_axi_arready) begin
            m_axi_arvalid <= 0; m_axi_rready <= 1;
            b_state <= 4; // RD_R
          end
        end
        4: begin // RD_R
          if (m_axi_rvalid) begin
            rdata_r <= m_axi_rdata; m_axi_rready <= 0;
            ready_r <= 1; b_state <= 0;
          end
        end
      endcase
    end
  end

  // Interconnect & Slaves instantiation (simplified for brevity, connects to AXI routing)
  wire [31:0] s0_awaddr, s0_wdata, s0_araddr, s0_rdata;
  wire [3:0] s0_wstrb; wire s0_awvalid, s0_awready, s0_wvalid, s0_wready, s0_bvalid, s0_bready, s0_arvalid, s0_arready, s0_rvalid, s0_rready;
  wire [1:0] s0_bresp, s0_rresp;
  wire [31:0] s1_awaddr, s1_wdata, s1_araddr, s1_rdata;
  wire [3:0] s1_wstrb; wire s1_awvalid, s1_awready, s1_wvalid, s1_wready, s1_bvalid, s1_bready, s1_arvalid, s1_arready, s1_rvalid, s1_rready;
  wire [1:0] s1_bresp, s1_rresp;
  wire [31:0] s2_awaddr, s2_wdata, s2_araddr, s2_rdata;
  wire [3:0] s2_wstrb; wire s2_awvalid, s2_awready, s2_wvalid, s2_wready, s2_bvalid, s2_bready, s2_arvalid, s2_arready, s2_rvalid, s2_rready;
  wire [1:0] s2_bresp, s2_rresp;

  axi_lite_interconnect u_ic (
    .clk(clk), .reset(reset),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb_r), .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
    .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),

    .s0_axi_awaddr(s0_awaddr), .s0_axi_awvalid(s0_awvalid), .s0_axi_awready(s0_awready),
    .s0_axi_wdata(s0_wdata), .s0_axi_wstrb(s0_wstrb), .s0_axi_wvalid(s0_wvalid), .s0_axi_wready(s0_wready),
    .s0_axi_bresp(s0_bresp), .s0_axi_bvalid(s0_bvalid), .s0_axi_bready(s0_bready),
    .s0_axi_araddr(s0_araddr), .s0_axi_arvalid(s0_arvalid), .s0_axi_arready(s0_arready),
    .s0_axi_rdata(s0_rdata), .s0_axi_rresp(s0_rresp), .s0_axi_rvalid(s0_rvalid), .s0_axi_rready(s0_rready),

    .s1_axi_awaddr(s1_awaddr), .s1_axi_awvalid(s1_awvalid), .s1_axi_awready(s1_awready),
    .s1_axi_wdata(s1_wdata), .s1_axi_wstrb(s1_wstrb), .s1_axi_wvalid(s1_wvalid), .s1_axi_wready(s1_wready),
    .s1_axi_bresp(s1_bresp), .s1_axi_bvalid(s1_bvalid), .s1_axi_bready(s1_bready),
    .s1_axi_araddr(s1_araddr), .s1_axi_arvalid(s1_arvalid), .s1_axi_arready(s1_arready),
    .s1_axi_rdata(s1_rdata), .s1_axi_rresp(s1_rresp), .s1_axi_rvalid(s1_rvalid), .s1_axi_rready(s1_rready),

    .s2_axi_awaddr(s2_awaddr), .s2_axi_awvalid(s2_awvalid), .s2_axi_awready(s2_awready),
    .s2_axi_wdata(s2_wdata), .s2_axi_wstrb(s2_wstrb), .s2_axi_wvalid(s2_wvalid), .s2_axi_wready(s2_wready),
    .s2_axi_bresp(s2_bresp), .s2_axi_bvalid(s2_bvalid), .s2_axi_bready(s2_bready),
    .s2_axi_araddr(s2_araddr), .s2_axi_arvalid(s2_arvalid), .s2_axi_arready(s2_arready),
    .s2_axi_rdata(s2_rdata), .s2_axi_rresp(s2_rresp), .s2_axi_rvalid(s2_rvalid), .s2_axi_rready(s2_rready)
  );

  rom u_rom (
    .clk(clk), .reset(reset),
    .awaddr(s0_awaddr), .awvalid(s0_awvalid), .awready(s0_awready),
    .wdata(s0_wdata), .wstrb(s0_wstrb), .wvalid(s0_wvalid), .wready(s0_wready),
    .bresp(s0_bresp), .bvalid(s0_bvalid), .bready(s0_bready),
    .araddr(s0_araddr), .arvalid(s0_arvalid), .arready(s0_arready),
    .rdata(s0_rdata), .rresp(s0_rresp), .rvalid(s0_rvalid), .rready(s0_rready)
  );

  sram u_sram (
    .clk(clk), .reset(reset),
    .awaddr(s1_awaddr), .awvalid(s1_awvalid), .awready(s1_awready),
    .wdata(s1_wdata), .wstrb(s1_wstrb), .wvalid(s1_wvalid), .wready(s1_wready),
    .bresp(s1_bresp), .bvalid(s1_bvalid), .bready(s1_bready),
    .araddr(s1_araddr), .arvalid(s1_arvalid), .arready(s1_arready),
    .rdata(s1_rdata), .rresp(s1_rresp), .rvalid(s1_rvalid), .rready(s1_rready)
  );

  uart_axi u_uart (
    .clk(clk), .reset(reset),
    .awaddr(s2_awaddr), .awvalid(s2_awvalid), .awready(s2_awready),
    .wdata(s2_wdata), .wstrb(s2_wstrb), .wvalid(s2_wvalid), .wready(s2_wready),
    .bresp(s2_bresp), .bvalid(s2_bvalid), .bready(s2_bready),
    .araddr(s2_araddr), .arvalid(s2_arvalid), .arready(s2_arready),
    .rdata(s2_rdata), .rresp(s2_rresp), .rvalid(s2_rvalid), .rready(s2_rready),
    .tx_pin(uart_tx), .rx_pin(uart_rx)
  );
endmodule
