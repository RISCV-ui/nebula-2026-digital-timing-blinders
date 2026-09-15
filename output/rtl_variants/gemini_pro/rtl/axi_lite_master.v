`timescale 1ns / 1ps

module axi_lite_master(clk,rst,
                       addr,addr_valid,data_out,read_write,data_in,done,
                       
                       m1_ar_addr,m1_ar_valid,m1_ar_ready,
                       m1_aw_addr,m1_aw_valid,m1_aw_ready,
                       m1_dr_data,m1_dr_valid,m1_dr_ready,m1_dr_resp,
                       m1_dw_data,m1_dw_valid,m1_dw_ready,m1_dw_strb,
                       m1_b_ready,m1_b_valid,m1_b_resp
                       );

input clk,rst;

input  [31:0] addr;
input         addr_valid;
input  [31:0] data_out;
input         read_write;
output reg [31:0] data_in;

// One-cycle completion pulse: the read data has been captured into data_in,
// or the write response has come back. A requester that holds addr_valid
// until its access finishes needs this; without it there is no way to tell a
// transaction in flight from one already done.
output reg        done;

output reg [31:0] m1_ar_addr;
output reg        m1_ar_valid;
input             m1_ar_ready;

output reg [31:0] m1_aw_addr;
output reg        m1_aw_valid;
input             m1_aw_ready;

input      [31:0] m1_dr_data;
input             m1_dr_valid;
output reg        m1_dr_ready;
input      [1:0]  m1_dr_resp;

output reg [31:0] m1_dw_data;
output reg        m1_dw_valid;
input             m1_dw_ready;
output reg [3:0]  m1_dw_strb;

output reg        m1_b_ready;
input             m1_b_valid;
input      [1:0]  m1_b_resp;


reg read_active;
reg write_active;
reg aw_complete;
reg dw_complete;
reg addr_valid_d;


always@(posedge clk)
begin

     if(rst)
     begin
          m1_ar_addr   <= 32'd0;
          m1_ar_valid  <= 1'b0;
          m1_dr_ready  <= 1'b0;

          m1_aw_addr   <= 32'd0;
          m1_aw_valid  <= 1'b0;

          m1_dw_data   <= 32'd0;
          m1_dw_valid  <= 1'b0;
          m1_dw_strb   <= 4'd0;

          m1_b_ready   <= 1'b0;

          data_in      <= 32'd0;
          done         <= 1'b0;

          read_active  <= 1'b0;
          write_active <= 1'b0;

          aw_complete  <= 1'b0;
          dw_complete  <= 1'b0;

          addr_valid_d <= 1'b0;
     end

     else
     begin

          addr_valid_d <= addr_valid;
          done         <= 1'b0;


          if(addr_valid && !addr_valid_d && !read_active && !write_active)
          begin

               if(read_write == 1'b0)
               begin
                    m1_ar_addr  <= addr;
                    m1_ar_valid <= 1'b1;
                    read_active <= 1'b1;
               end

               else
               begin
                    m1_aw_addr   <= addr;
                    m1_aw_valid  <= 1'b1;

                    m1_dw_data   <= data_out;
                    m1_dw_valid  <= 1'b1;
                    m1_dw_strb   <= 4'b1111;

                    write_active <= 1'b1;
               end

          end


          if(m1_ar_valid && m1_ar_ready)
          begin
               m1_ar_valid <= 1'b0;
               m1_ar_addr  <= 32'd0;
               m1_dr_ready <= 1'b1;
          end


          if(m1_dr_valid && m1_dr_ready)
          begin
               data_in      <= m1_dr_data;
               m1_dr_ready  <= 1'b0;
               read_active  <= 1'b0;
               done         <= 1'b1;
          end


          if(m1_aw_valid && m1_aw_ready)
          begin
               m1_aw_valid <= 1'b0;
               m1_aw_addr  <= 32'd0;
               aw_complete <= 1'b1;
          end


          if(m1_dw_valid && m1_dw_ready)
          begin
               m1_dw_valid <= 1'b0;
               m1_dw_data  <= 32'd0;
               m1_dw_strb  <= 4'd0;
               dw_complete <= 1'b1;
          end


          if(aw_complete && dw_complete && !m1_b_ready)
          begin
               m1_b_ready <= 1'b1;
          end


          if(m1_b_valid && m1_b_ready)
          begin
               m1_b_ready   <= 1'b0;

               aw_complete   <= 1'b0;
               dw_complete   <= 1'b0;

               write_active  <= 1'b0;
               done          <= 1'b1;
          end

     end

end


// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     m1_dr_resp, m1_b_resp,
                     1'b0};

endmodule
