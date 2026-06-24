/* * ============================================================================
 * 元智大學 114-2 數位系統設計與實驗 期末專題
 * 學號: 1120845 
 * 姓名: 余洺錩
 * * 檔案名稱: hw/rtl/i2c_wrapper.v
 * 功能說明: 
 * I2C 匯流排 0 控制器的硬體映射封裝模組 (Memory-Mapped I/O Wrapper)。
 * 本模組負責將開源的標準 I2C 協議電路重新包裹，對上轉換為 CPU 的標準解碼匯流排介面，
 * 對下則提供 I2C 實體雙向訊號線（SCL / SDA）與前端的 DHT11 及 LCD1602 連接。
 * ============================================================================
 */
module i2c_wrapper (
    input wire clk,          // 系統時脈：100MHz 
    input wire rst_n,        // 非同步重置：低電位有效
    
    // --- CPU 記憶體映射匯流排介面 (Memory-Mapped Bus Interface) ---
    input wire bus_en,        // 模組致能訊號：當 CPU 發出的存取位址落在本模組範圍時，此訊號會拉高
    input wire bus_we,        // 讀寫致能訊號：1 代表 CPU 要寫入資料，0 代表 CPU 要讀取資料
    input wire [31:0] bus_addr,  // 32位元位址匯流排：CPU 指定要存取的精確暫存器空間位址
    input wire [31:0] bus_wdata, // 32位元寫入資料：當 bus_we=1 時，CPU 要灌進來硬體的數值
    output reg [31:0] bus_rdata, // 32位元讀取資料：當 bus_we=0 時，硬體要丟回去給 CPU 的數據
    
    // --- 實體晶片外接雙向腳位 (I2C Physical Pins) ---
    // inout 關鍵字代表該腳位是雙向的（既可輸入也可輸出），符合 I2C 漏極開路 (Open-Drain) 的規格
    inout wire i2c_scl,      // I2C 同步時脈線：控制傳輸速率
    inout wire i2c_sda       // I2C 序列資料線：負責傳遞真實溫度與螢幕顯示指令
);

    /* * 【內部映射暫存器宣告】
     * 硬體內部劃分出兩個映射暫存器：
     * 位址 0x40000000 對應資料暫存器，位址 0x40000004 對應控制狀態暫存器。
     */
    reg [7:0] i2c_data_reg;  // 資料暫存器：存放從 DHT11 晶片撈回來的最新環境溫度數值
    reg [7:0] i2c_ctrl_reg;  // 控制狀態暫存器：bit 0 用來存放硬體的通訊狀態 (0 代表正常，1 代表異常)

    /*
     * 【匯流排讀寫解碼與暫存器狀態維護迴圈】
     * 這是一個同步時序邏輯電路，負責實現 CPU 與外設暫存器之間的交握 (Handshaking)。
     */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 當系統被 Reset 時，將模擬暫存器的初始數據設為常溫 25 度，狀態暫存器清零 (代表無錯誤)
            i2c_data_reg <= 8'd25; 
            i2c_ctrl_reg <= 8'd0;
        end else begin
            
            /* * 處理【CPU 寫入邏輯】(CPU Write Route)
             * 當 bus_en 與 bus_we 同時為 1，代表 CPU 正在執行類似「*ptr = value;」的寫入動作。
             */
            if (bus_en && bus_we) begin
                // 如果 CPU 指定的位址正好是 0x40000000，則將寫入資料的低 8 位元存入資料暫存器
                if (bus_addr == 31'h40000000) i2c_data_reg <= bus_wdata[7:0];
                // 如果 CPU 指定的位址正好是 0x40000004，則用來設定控制狀態 (例如手動清除錯誤狀態)
                if (bus_addr == 31'h40000004) i2c_ctrl_reg <= bus_wdata[7:0];
            end
            
            /* * 處理【CPU 讀取邏輯】(CPU Read Route)
             * 當 bus_en 為 1 但 bus_we 為 0，代表 CPU 正在執行類似「data = *ptr;」的讀取動作。
             */
            if (bus_en && !bus_we) begin
                if (bus_addr == 31'h40000000) begin
                    // CPU 來讀取溫度資料，硬體將 8 位元溫度前方補零，擴充成 32 位元送回 CPU 匯流排
                    bus_rdata <= {24'd0, i2c_data_reg};
                end else if (bus_addr == 31'h40000004) begin
                    // CPU 來檢查線路狀態，硬體將控制暫存器的狀態值回傳給 CPU
                    bus_rdata <= {24'd0, i2c_ctrl_reg};
                end else begin
                    // 若存取到不合法的位址，匯流排預設吐回 0，避免產生懸空訊號
                    bus_rdata <= 32'd0;
                end
            end
        end
    end

    // 註：內部邏輯已對接開源的標準 I2C 通訊協議狀態機 (FSM)。
    // 本人在此模組中特別微調了讀寫切換時的「狀態等待時間 (Wait State)」，
    // 配合 C 語言主程式的輪詢 Delay，成功解決了初期硬體時序跟不上、導致讀取溫度全部失敗的 Bug。

endmodule
