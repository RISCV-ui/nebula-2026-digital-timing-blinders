//`timescale 1ns / 1ps

//module axi_lite_dma_config(clk_1,rst_1, clk_2, rst_2,
                     
//                     s1_ar_addr, s1_ar_valid, s1_ar_ready, 
//                     s1_aw_addr, s1_aw_valid, s1_aw_ready, 
//                     s1_dr_data, s1_dr_valid, s1_dr_ready,s1_dr_resp,
//                     s1_dw_data, s1_dw_valid, s1_dw_ready,s1_dw_strb, 
//                     s1_b_ready, s1_b_valid,  s1_b_resp ,
                     
//                     m2_ar_addr, m2_ar_valid, m2_ar_ready,
//                     m2_aw_addr, m2_aw_valid, m2_aw_ready,
//                     m2_dr_data, m2_dr_valid, m2_dr_ready,
//                     m2_dw_data, m2_dw_valid, m2_dw_ready,
//                     m2_b_ready,       m2_b_valid,  m2_b_resp
 
//    ); 
     
// input clk_1,rst_1 , clk_2, rst_2;

////// raed addr  
//input  wire [31:0] s1_ar_addr; 
//input  wire        s1_ar_valid; 
//output             s1_ar_ready; 
 
 
////// write addr  
//input  wire [31:0] s1_aw_addr; 
//input  wire        s1_aw_valid; 
//output wire        s1_aw_ready; 
 
/////// read data 
//output   [31:0] s1_dr_data; 
//output          s1_dr_valid; 
//output   [1:0]  s1_dr_resp ; 
//input           s1_dr_ready; 

 
//////  write data  
//input  wire [31:0] s1_dw_data; 
//input  wire        s1_dw_valid; 
//output wire        s1_dw_ready; 
//input wire [3:0]   s1_dw_strb;    // Byte write enable 

 
///// buffer 
//input          s1_b_ready; 
//output   reg       s1_b_valid; 
//output   [1:0]  s1_b_resp; 
 
// ///// master 
 
//output reg    [31:0] m2_ar_addr;
//output reg           m2_ar_valid;
//input                m2_ar_ready;

//output reg    [31:0] m2_aw_addr;
//output reg           m2_aw_valid;
//input                m2_aw_ready;

//input         [31:0] m2_dr_data;
//input                m2_dr_valid;
//output reg           m2_dr_ready;

//output reg    [31:0] m2_dw_data;
//output reg           m2_dw_valid;
//input                m2_dw_ready;

//output reg           m2_b_ready;
//input                m2_b_valid;
//input         [1:0]  m2_b_resp;
 
 
 
 
 
 
 
 
 
// //// wire
//wire full_r_axi, empty_r_axi ;
//wire [31:0]fifo_read_data_axi,fifo_data_write;
//wire write_en_axi, read_en_axi;
//wire [40:0]fifo_write_data_axi ,fifo_data_read;

///////  peripheral 
//wire read_write,addr_valid;
//wire [31:0]data_out,data_in ,addr ;


// ///// regs
// reg [31:0]addr_r_w , data_reg ;
// reg addr_r_comp,addr_w_comp ,data_w_comp ;
 

 
///////////// 
    

  
///////// peripheral dma 
//dma_controller(clk,rst, 
//                      addr,addr_valid,read_write,
//                      data_in,data_out,
//                      addr_src_dma,addr_valid_src_dma,read_req_valid_src_dma,data_in_src_dma,
//                      addr_dest_dma,addr_valid_dest_dma,write_req_valid_dest_dma,data_out_dest_dma,
//                      int_out_dma,dma_bus_req,dam_bus_req_burst,dma_bus_grant
         
//                      );
                      
/////// master dma interface 

//assign read_req_valid_src_dma =  m2_dr_data ; 
//assign data_in_src_dma        =  m2_dr_valid ;
//assign m2_dr_read             =  !addr_r_comp;
//assign write_req_valid_dest_dma  = m2_dw_data


//always@(posedge clk )
//begin
//     if(rst)
//     begin
//          addr_r_comp <=1'b0;



//     end
     
//     else
//     begin
//           ///// read master 

//             if(addr_valid_src_dma)
//             begin          
//                  m2_ar_addr <=  addr_src_dma ;
//                  m2_ar_valid <= 1'b1;
//                  addr_r_comp <=1'b1;
//             end
             
//             if(m2_ar_valid && s1_aw_ready) 
//              begin
//                    m2_ar_addr <=  32'd0;   
//                    m2_ar_valid <= 1'b0; 
       
              
//              end  
                
//              if(m2_dr_valid && s1_dw_ready) 
//              begin
 
//                    addr_m_comp <=1'b0;           
              
//              end
              
//              ////// write 
//              if(addr_valid_dest_dma)
//             begin          
//                  m2_aw_addr <=  addr_dest_dma ;
//                  m2_aw_valid <= 1'b1;
//                  addr_w_comp <=1'b1;
//             end
              
              
                 
      
      
      
      
      
//      end      
           
      
      
     

//end

                                           
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      
                      

//assign addr       = addr_r_w;
//assign addr_valid = addr_r_comp;
//assign read_write = addr_w_comp;
//assign data_in    = data_reg;


///////////////
                                                    

////// read
//assign s1_ar_ready  = !addr_r_comp ;  
//assign s1_dr_data   = data_out ; 
//assign s1_dr_valid  = addr_r_comp ;
//assign s1_dr_resp   = 2'd0 ;


////// write 
//assign s1_aw_ready = !addr_w_comp   ; 
//assign s1_dw_ready =  addr_w_comp; 
//assign s1_b_resp   = 2'd0;    




///////write



/////// read 
//always@(posedge clk_1 )
//begin                          
//     if(rst_1)
//     begin
//          addr_r_w <= 32'd0;
//          addr_r_comp <= 1'd0;
//          addr_w_comp <= 1'b0;
//          data_w_comp <= 1'b0;
//          s1_b_valid <= 1'b0; 
//          data_reg   <= 32'd0; 

 
//     end
//     else
//     begin  //// read addr
//           if(s1_ar_valid && s1_ar_ready)
//           begin
//               addr_r_comp <= 1'b1;
//               addr_r_w <= s1_ar_addr;
//           end
//          //// read clear 
//           else if(s1_dr_valid && s1_dr_ready)
//           begin
//               addr_r_comp <= 1'b0;
//               addr_r_w <= 32'd0;
//           end
           
           
//            //// write addr
//           if((s1_aw_valid && s1_aw_ready))
//           begin
//                addr_r_w    <= s1_aw_addr;
//                addr_w_comp <= 1'b1;
//           end
           
//           //// write data 
//           if((s1_dw_valid && s1_dw_ready))
//           begin
//                 data_reg   <= s1_dw_data; 
//                 data_w_comp <= 1'b1;
//           end
           
           
//           if(data_w_comp && addr_w_comp && !s1_b_valid )
//           begin
//                data_w_comp <= 1'b0;
//                addr_w_comp <= 1'b0;
//                data_reg   <=  32'd0;  
//                s1_b_valid <= 1'b1;   
//           end
           
//           else if(s1_b_valid && s1_b_ready)
//           begin
//                 s1_b_valid <= 1'b0;   
//           end
     
     
//     end
 
//end  
 
                          
                          
                          
                          

      
//endmodule 

`timescale 1ns / 1ps

module axi_lite_dma_config(clk_1,rst_1, clk_2, rst_2,
                     
                     s1_ar_addr, s1_ar_valid, s1_ar_ready, 
                     s1_aw_addr, s1_aw_valid, s1_aw_ready, 
                     s1_dr_data, s1_dr_valid, s1_dr_ready,s1_dr_resp,
                     s1_dw_data, s1_dw_valid, s1_dw_ready,s1_dw_strb, 
                     s1_b_ready, s1_b_valid, s1_b_resp ,
                     
                     m2_ar_addr, m2_ar_valid, m2_ar_ready,
                     m2_aw_addr, m2_aw_valid, m2_aw_ready,
                     m2_dr_data, m2_dr_valid, m2_dr_ready,
                     m2_dw_data, m2_dw_valid, m2_dw_ready,
                     m2_b_ready, m2_b_valid, m2_b_resp
 
    ); 
     
input clk_1,rst_1 , clk_2, rst_2;

input  wire [31:0] s1_ar_addr; 
input  wire        s1_ar_valid; 
output             s1_ar_ready; 
 
input  wire [31:0] s1_aw_addr; 
input  wire        s1_aw_valid; 
output wire        s1_aw_ready; 
 
output   [31:0] s1_dr_data; 
output          s1_dr_valid; 
output   [1:0]  s1_dr_resp ; 
input           s1_dr_ready; 

input  wire [31:0] s1_dw_data; 
input  wire        s1_dw_valid; 
output wire        s1_dw_ready; 
input wire [3:0]   s1_dw_strb;    

input               s1_b_ready; 
output reg           s1_b_valid; 
output [1:0]         s1_b_resp; 
 
output reg [31:0]    m2_ar_addr;
output reg           m2_ar_valid;
input                m2_ar_ready;

output reg [31:0]    m2_aw_addr;
output reg           m2_aw_valid;
input                m2_aw_ready;

input [31:0]         m2_dr_data;
input                m2_dr_valid;
output reg           m2_dr_ready;

output reg [31:0]    m2_dw_data;
output reg           m2_dw_valid;
input                m2_dw_ready;

output reg           m2_b_ready;
input                m2_b_valid;
input [1:0]          m2_b_resp;

wire read_write,addr_valid;
wire [31:0]data_out,data_in,addr;

wire [31:0]addr_src_dma;
wire addr_valid_src_dma;
wire read_req_valid_src_dma;
wire [31:0]data_in_src_dma;

wire [31:0]addr_dest_dma;
wire addr_valid_dest_dma;
wire write_req_valid_dest_dma;
wire write_ack_dest_dma;
wire [31:0]data_out_dest_dma;

wire int_out_dma;
wire dma_bus_req;
wire dam_bus_req_burst;
wire dma_bus_grant;

reg [31:0]addr_r_w,data_reg;
reg addr_r_comp,addr_w_comp,data_w_comp;

reg m_addr_r_comp;
reg m_addr_w_comp;
reg m_data_w_comp;
reg m_write_active;


dma_controller dma_0(clk_2,rst_2, 
                     addr,addr_valid,read_write,
                     data_in,data_out,
                     addr_src_dma,addr_valid_src_dma,read_req_valid_src_dma,data_in_src_dma,
                     addr_dest_dma,addr_valid_dest_dma,write_req_valid_dest_dma,write_ack_dest_dma,data_out_dest_dma,
                     int_out_dma,dma_bus_req,dam_bus_req_burst,dma_bus_grant
                     );


assign dma_bus_grant = 1'b1;

assign data_in_src_dma = m2_dr_data;

assign read_req_valid_src_dma = m2_dr_valid && m2_dr_ready;

// Write-side acknowledge, symmetric with the read side above: the write
// data beat has been accepted by the slave.
assign write_ack_dest_dma = m2_dw_valid && m2_dw_ready;


always@(posedge clk_2)
begin

     if(rst_2)
     begin
          m2_ar_addr     <= 32'd0;
          m2_ar_valid    <= 1'b0;
          m2_dr_ready    <= 1'b0;

          m2_aw_addr     <= 32'd0;
          m2_aw_valid    <= 1'b0;

          m2_dw_data     <= 32'd0;
          m2_dw_valid    <= 1'b0;

          m2_b_ready     <= 1'b0;

          m_addr_r_comp  <= 1'b0;
          m_addr_w_comp  <= 1'b0;
          m_data_w_comp  <= 1'b0;
          m_write_active <= 1'b0;
     end

     else
     begin

          if(addr_valid_src_dma && !m_addr_r_comp && !m2_ar_valid)
          begin
               m2_ar_addr    <= addr_src_dma;
               m2_ar_valid   <= 1'b1;
               m_addr_r_comp <= 1'b1;
          end

          if(m2_ar_valid && m2_ar_ready)
          begin
               m2_ar_valid <= 1'b0;
               m2_ar_addr  <= 32'd0;
               m2_dr_ready <= 1'b1;
          end

          if(m2_dr_valid && m2_dr_ready)
          begin
               m2_dr_ready   <= 1'b0;
               m_addr_r_comp <= 1'b0;
          end


          if(addr_valid_dest_dma && !m_addr_w_comp)
          begin
               m2_aw_addr     <= addr_dest_dma;
               m2_aw_valid    <= 1'b1;
               m_write_active <= 1'b1;
          end

          if(write_req_valid_dest_dma && !m_data_w_comp)
          begin
               m2_dw_data     <= data_out_dest_dma;
               m2_dw_valid    <= 1'b1;
               m_write_active <= 1'b1;
          end

          if(m2_aw_valid && m2_aw_ready)
          begin
               m2_aw_valid   <= 1'b0;
               m2_aw_addr    <= 32'd0;
               m_addr_w_comp <= 1'b1;
          end

          if(m2_dw_valid && m2_dw_ready)
          begin
               m2_dw_valid   <= 1'b0;
               m2_dw_data    <= 32'd0;
               m_data_w_comp <= 1'b1;
          end

          if(m_write_active &&
             m_addr_w_comp &&
             m_data_w_comp &&
             !m2_b_ready)
          begin
               m2_b_ready <= 1'b1;
          end

          if(m2_b_valid && m2_b_ready)
          begin
               m2_b_ready     <= 1'b0;
               m_addr_w_comp  <= 1'b0;
               m_data_w_comp  <= 1'b0;
               m_write_active <= 1'b0;
          end

     end

end


assign addr       = addr_r_w;
assign addr_valid = addr_r_comp || (addr_w_comp && data_w_comp);
assign read_write = addr_w_comp && data_w_comp;
assign data_in    = data_reg;


assign s1_ar_ready = !addr_r_comp && !addr_w_comp && !s1_b_valid;

assign s1_dr_data  = data_out;

assign s1_dr_valid = addr_r_comp;

assign s1_dr_resp  = 2'd0;


assign s1_aw_ready = !addr_w_comp && !addr_r_comp && !s1_b_valid;

assign s1_dw_ready = addr_w_comp && !data_w_comp;

assign s1_b_resp   = 2'd0;


always@(posedge clk_1)
begin

     if(rst_1)
     begin
          addr_r_w    <= 32'd0;
          addr_r_comp <= 1'b0;
          addr_w_comp <= 1'b0;
          data_w_comp <= 1'b0;
          s1_b_valid  <= 1'b0;
          data_reg    <= 32'd0;
     end

     else
     begin

          if(s1_ar_valid && s1_ar_ready)
          begin
               addr_r_comp <= 1'b1;
               addr_r_w    <= s1_ar_addr;
          end

          else if(s1_dr_valid && s1_dr_ready)
          begin
               addr_r_comp <= 1'b0;
               addr_r_w    <= 32'd0;
          end


          if(s1_aw_valid && s1_aw_ready)
          begin
               addr_r_w    <= s1_aw_addr;
               addr_w_comp <= 1'b1;
          end


          if(s1_dw_valid && s1_dw_ready)
          begin
               data_reg    <= s1_dw_data;
               data_w_comp <= 1'b1;
          end


          if(data_w_comp && addr_w_comp && !s1_b_valid)
          begin
               data_w_comp <= 1'b0;
               addr_w_comp <= 1'b0;
               data_reg    <= 32'd0;
               addr_r_w    <= 32'd0;
               s1_b_valid  <= 1'b1;
          end

          else if(s1_b_valid && s1_b_ready)
          begin
               s1_b_valid <= 1'b0;
          end

     end

end



// Intentionally unused. Reduced into a dummy net so the design stays
// warning-free under `verilator --lint-only -Wall` without suppressing
// UNUSEDSIGNAL globally, which would hide genuinely dead logic later.
wire _unused_ok = &{1'b0,
                     s1_dw_strb, m2_b_resp, int_out_dma, dma_bus_req, dam_bus_req_burst,
                     1'b0};

endmodule

