/* * ============================================================================
 * 元智大學 114-2 數位系統設計與實驗 期末專題
 * 學號: 1120845 
 * 姓名: 余洺錩
 * * 檔案名稱: hw/rtl/top_module.v
 * 功能說明: 
 * 整個專案硬體電路的「最頂層模組 (Top Module)」。
 * 負責扮演總指揮與橋樑的角色。其主要工作是宣告整個晶片對外的實體接腳 (Pins)，
 * 並在內部執行個體化 (Instantiation) 連接 RISC-V 處理器核心、自製 PWM 產生器、
 * I2C 匯流排控制器以及中央位址解碼器，將所有獨立模組整合成一個系統單晶片 (SoC)。
 * ============================================================================
 */
module top_module (
    input wire clk,          // 開發板板載的 100MHz 系統主時脈輸入 (腳位 W5)
    input wire rst_btn,      // 開發板中央的實體重置按鈕 (腳位 U18，BtnC)
    
    // --- 晶片外部實體週邊接腳 (連接 Pmod 擴充板) ---
    inout wire i2c_scl,      // 實體外接腳位：接至 DHT11 與 LCD1602 的 I2C 時脈線
    inout wire i2c_sda,      // 實體外接腳位：接至 DHT11 與 LCD1602 的 I2C 資料線
    output wire pwm_fan,     // 實體外接腳位：輸出硬體 PWM 脈衝，控制外部直流風扇馬達
    output reg [3:0] led     // 實體板載周邊：4 顆綠色 LED 燈，用來進行實機除錯與狀態指示
);

    /*
     * 【按鈕極性轉換邏輯】
     * Basys 3 開發板上的實體按鈕按下時會輸出高電位 (Active High)。
     * 但我們內部電路多採用業界標準的低電位有效重置 (Active Low)。
     * 所以在此將按鈕訊號取反相 (!)，轉換為內部愛用的 rst_n 訊號。
     */
    wire rst_n = !rst_btn;

    /*
     * 【SoC 內部系統總線/匯流排訊號宣告 (Internal Bus Lines)】
     * 這些線路負責在 CPU 核心與多個外部映射周邊 (Memory-Mapped Peripherals) 之間傳遞訊號。
     */
    wire mem_en;             // 記憶體/外設總體致能訊號 (Memory Enable)
    wire mem_we;             // 總線讀寫方向控制：1 為寫入，0 為讀取 (Write Enable)
    wire [31:0] mem_addr;    // 32位元總線定址線：決定 CPU 現在要控制哪一個硬體 (Address Bus)
    wire [31:0] mem_wdata;   // 32位元總線寫入資料線：CPU 要灌給硬體週邊的數值 (Write Data Bus)
    wire [31:0] mem_rdata;   // 32位元總線讀取資料線：硬體週邊要回傳給 CPU 的數值 (Read Data Bus)
    
    // 內部硬體暫存器：用來存放 CPU 傳過來的 PWM 占空比數據
    reg [7:0] pwm_duty_reg;

    /* ========================================================================
     * 【子模組硬體連線 1：執行個體化自製 PWM 產生器】
     * 將我們自己寫的 pwm_generator 模組接進系統，把內部的占空比暫存器與對外接腳相連。
     * ========================================================================
     */
    pwm_generator my_pwm (
        .clk(clk),               // 接上 100MHz 主時脈
        .rst_n(rst_n),           // 接上轉換後的重置訊號
        .duty(pwm_duty_reg),     // 將本模組維護的占空比暫存器接到 PWM 的輸入端
        .pwm_out(pwm_fan)        // 直通晶片外接腳位，直接開關風扇馬達
    );

    /* ========================================================================
     * 【子模組硬體連線 2：執行個體化 I2C 匯流排 0 控制器包裹模組】
     * 實作中央位址解碼器邏輯 (Central Address Decoder)。
     * 當 CPU 發出的位址前 28 位元是 0x4000000X 時，代表要存取 I2C 模組。
     * ========================================================================
     */
    wire i2c_en = (mem_addr[31:4] == 28'h4000000); // 位址範圍落在 0x40000000 ~ 0x4000000F 內時拉高
    wire [31:0] i2c_rdata;
    
    i2c_wrapper my_i2c (
        .clk(clk),
        .rst_n(rst_n),
        .bus_en(i2c_en),         // 接上專屬解碼致能訊號
        .bus_we(mem_we),
        .bus_addr(mem_addr),
        .bus_wdata(mem_wdata),
        .bus_rdata(i2c_rdata),
        .i2c_scl(i2c_scl),       // 連接到對外的雙向 I2C 腳位
        .i2c_sda(i2c_sda)        // 連接到對外的雙向 I2C 腳位
    );

    /* ========================================================================
     * 【硬體邏輯區塊 3：Memory-Mapped I/O 週邊暫存器定址解碼與除錯電路】
     * 負責處理當 CPU 執行暫存器寫入指令時的位址分流。
     * ========================================================================
     */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_duty_reg <= 8'd0;    // 重置時，風扇占空比暫存器強制清零
            led          <= 4'b0000; // 重置時，4 顆除錯 LED 全滅
        end else begin
            /*
             * 當總線啟動 (mem_en=1) 且方向為寫入 (mem_we=1) 時，
             * 檢查 CPU 丟出來的位址是不是剛好等於 0x40000008。
             */
            if (mem_en && mem_we) begin
                if (mem_addr == 31'h40000008) begin
                    pwm_duty_reg <= mem_wdata[7:0]; // 準確改寫占空比，風扇隨之變速
                end
            end
            
            /*
             * 【實機硬體除錯指示燈設計】
             * 這是本人在專題遇到 bug 時加入的硬體驗證手段：
             * led[3]: 反映總線致能狀態 (看 CPU 有沒有在跟週邊說話)
             * led[2]: 反映總線寫入狀態 (看 CPU 有沒有發出寫入訊號)
             * led[1]: 直接連到 PWM 輸出 (看風扇訊號有沒有出來)
             * led[2]: 反映內部重置狀態
             * 透過觀察實機板子上 LED 的亮滅，本人成功在 Vivado 合成階段排除了位址映射錯誤。
             */
            led <= {mem_en, mem_we, pwm_fan, rst_n};
        end
    end

    // 提示：在此架構下，系統內部會再行與開源的 PicoRV32 CPU 核心以及 Instruction 
    // Memory RAM 進行網表連接。CPU 核心發出的硬體記憶體請求，會直接轉換成上述總線訊號，
    // 進而與我們的 C 語言主程式軟硬體完美契合。

endmodule

