## ============================================================================
## 元智大學 114-2 數位系統設計與實驗 期末專題腳位約束檔
## 學號: 1120845 
## 姓名: 余洺錩
## 開發板型號: Digilent Basys 3 (Artix-7 FPGA)
## 
## 檔案名稱: hw/constrs/Basys3.xdc
## 功能說明: 
##   Xilinx Vivado 在進行實體佈線 (Implementation) 時的最高指導約束檔。
##   負責把 Verilog 頂層模組 (top_module) 的內部抽象訊號名稱，
##   與 FPGA 晶片上實體的金屬引腳 (Pins) 一對一綁定，並設定其電子訊號電壓標準。
## ============================================================================

## ----------------------------------------------------------------------------
## 1. 系統主時脈訊號設定 (System Clock)
## ----------------------------------------------------------------------------
## 將 Verilog 裡面的 clk 訊號綁定到板子上的 W5 引腳 (這是一顆 100 MHz 的主時脈震盪器)
set_property PACKAGE_PIN W5 [get_ports clk]							
	## 設定這個引腳的電子電壓規格為 3.3V LVCMOS 數位電平標準
	set_property IOSTANDARD LVCMOS33 [get_ports clk]
	## 建立時序約束：告訴 Vivado 布線工具這個時脈週期是 10.00 奈秒 (10ns 代表 100MHz)，
	## 且工作週期各佔一半 (0ns到5ns是高電位)，這對硬體時序合成收斂 (Timing Convergence) 極為重要！
	create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## ----------------------------------------------------------------------------
## 2. 全域硬體重置按鈕設定 (System Global Reset Button)
## ----------------------------------------------------------------------------
## 將 rst_btn 綁定到板子正中央的實體按鈕 BtnC (引腳位址 U18)
## 按下時會送出 3.3V 高電位，用來觸發我們在硬體裡設計的非同步重置復位線
set_property PACKAGE_PIN U18 [get_ports rst_btn]						
	set_property IOSTANDARD LVCMOS33 [get_ports rst_btn]

## ----------------------------------------------------------------------------
## 3. 板載除錯狀態指示燈設定 (On-board Debug LEDs)
## ----------------------------------------------------------------------------
## 將 4 位元的 led 陣列分別對接到板子上最右邊的 4 顆綠色實體發光二極體 (LD0 ~ LD3)
## 用來即時在實機觀測 Memory-Mapped I/O 是否正常工作，不需依賴複雜的模擬工具
set_property PACKAGE_PIN U16 [get_ports {led[0]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property PACKAGE_PIN RX19 [get_ports {led[2]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property PACKAGE_PIN U19 [get_ports {led[3]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

## ----------------------------------------------------------------------------
## 4. Pmod 外接週邊腳位配置 (External Peripheral Interface - Pmod JA)
## ----------------------------------------------------------------------------
## 為了接上從實驗盒借來的 DHT11、LCD1602 與外購的風扇馬達，我們必須啟用 Pmod JA 擴充槽。

## 引腳 JA1 (晶片引腳 J1)：輸出我們自製的 PWM 控制訊號給馬達驅動板，調控風扇轉速
set_property PACKAGE_PIN J1 [get_ports pwm_fan]					
	set_property IOSTANDARD LVCMOS33 [get_ports pwm_fan]

## 引腳 JA2 (晶片引腳 L2)：作為 I2C 匯流排 0 的序列時脈線 (SCL)，通往 DHT11 與 LCD1602
set_property PACKAGE_PIN L2 [get_ports i2c_scl]					
	set_property IOSTANDARD LVCMOS33 [get_ports i2c_scl]

## 引腳 JA3 (晶片引腳 J2)：作為 I2C 匯流排 0 的序列資料線 (SDA)，負責雙向傳遞數值
set_property PACKAGE_PIN J2 [get_ports i2c_sda]					
	set_property IOSTANDARD LVCMOS33 [get_ports i2c_sda]
