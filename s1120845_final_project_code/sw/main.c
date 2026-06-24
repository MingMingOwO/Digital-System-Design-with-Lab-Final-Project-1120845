/* * ============================================================================
 * 元智大學 114-2 數位系統設計與實驗 期末專題成果報告程式碼
 * 學號: 1120845 
 * 姓名: 余洺錩
 * 系級: 電機工程學系乙組
 * * 檔案名稱: sw/main.c
 * 功能說明: 
 * 運行於 RISC-V (PicoRV32) 核心上的嵌入式 C 語言主程式。
 * 核心邏輯採用輪詢 (Polling) 機制，透過記憶體映射 I/O (Memory-Mapped I/O) 
 * 讀取 I2C 匯流排上的 DHT11 溫度感測器數值，並根據 28 度的門檻值控制自製的 
 * PWM 產生器暫存器來調節風扇馬達轉速，同時將狀態即時動態更新至 LCD1602 顯示螢幕。
 * ============================================================================
 */

/* * 【記憶體映射 I/O (Memory-Mapped I/O) 位址定義】
 * 透過指標 (Pointer) 將特定的暫存器硬體位址映射到軟體變數中。
 * volatile 關鍵字非常重要：它告訴編譯器這個位址的值是由外部硬體動態改變的，
 * 阻止編譯器進行最佳化 (Optimization)，確保每次都會老老實實去讀寫實體硬體。
 */
// I2C 匯流排 0 的資料暫存器：用來讀取或寫入 I2C 傳輸的 8-bit 資料
#define I2C_BUS0_DATA_REG  (*(volatile unsigned int *)0x40000000)

// I2C 匯流排 0 的控制與狀態暫存器：用來確認目前硬體傳輸狀態 (例如是否忙碌或出錯)
#define I2C_BUS0_CTRL_REG  (*(volatile unsigned int *)0x40000004)

// 自製 PWM 產生器的占空比暫存器：寫入 0~255 來決定風扇轉速 (0 為停止，255 為全速)
#define PWM_DUTY_REG       (*(volatile unsigned int *)0x40000008)

// LCD1602 螢幕的控制/資料暫存器：用來發送控制指令 (指令模式) 或顯示字元 (資料模式)
#define LCD_DATA_REG       (*(volatile unsigned int *)0x4000000C)

// 定義系統防呆異常代碼：當 I2C 讀取超時或斷線時，硬體會回傳 0xFF 代表錯誤
#define ERROR_CODE         0xFF

/**
 * @brief 精確軟體延遲函數 (Software Delay)
 * @details 因為嵌入式系統剛上電時，硬體週邊 (如 LCD、感測器) 的反應速度比 CPU 慢很多，
 * 必須透過空迴圈讓 CPU 等待一下，硬體才能正確接收下一個指令。
 * @param ms 要延遲的毫秒數 (Milliseconds)
 */
void delay_ms(int ms) {
    volatile int i, j;
    for (i = 0; i < ms; i++) {
        // 內層迴圈次數是根據 CPU 主頻估算出來的，用來消耗 CPU 週期達到大約 1 毫秒的延遲
        for (j = 0; j < 4000; j++) {
            // 什麼都不做，單純消耗時間
        }
    }
}

/**
 * @brief LCD1602 顯示螢幕初始化函數
 * @details 依照 LCD1602 的硬體規格書順序進行初始化。剛上電時必須給予足夠延遲，
 * 並連續發送功能設定指令，才能將螢幕切換到正確的顯示模式。
 */
void lcd_init() {
    // 剛上電先等 20 毫秒，讓 LCD 內部電路電壓穩定
    delay_ms(20); 
    
    // 發送 0x38 指令：設定為 8 位元資料介面、2 行顯示、5x7 點陣字型
    LCD_DATA_REG = 0x38; 
    delay_ms(5); // 等待 LCD 硬體處理指令
    
    // 發送 0x0C 指令：開啟整體顯示畫面、關閉游標閃爍 (避免畫面看起來一直閃)
    LCD_DATA_REG = 0x0C; 
    delay_ms(5);
    
    // 發送 0x01 指令：清空螢幕上原本殘留的所有游標與顯示資料，並將游標移回左上角首位
    LCD_DATA_REG = 0x01; 
    delay_ms(5);
}

/**
 * @brief 在 LCD1602 螢幕上輸出連續字串
 * @details 利用 C 語言指標輪詢字串中的每個字元，直到遇到字串結尾符號 '\0' 為止。
 * @param str 指向要顯示的字串常數指標
 */
void lcd_print_msg(const char *str) {
    while (*str) {
        // 將當前指標指向的字元寫入記憶體映射暫存器，硬體解碼後會直接顯示在螢幕上
        LCD_DATA_REG = *str; 
        str++;        // 指標移向底下的下一個字元
        delay_ms(1);  // 給予 LCD 硬體 1 毫秒的寫入緩衝時間
    }
}

/**
 * @brief 透過 I2C 匯流排 0 讀取前端 DHT11 的環境溫度
 * @details 軟體透過讀取狀態暫存器來實作輪詢 (Polling)。
 * @return int 傳回讀到的溫度整數值 (單位：°C)；若感測器斷線則傳回 ERROR_CODE (0xFF)。
 */
int i2c_read_dht11_temp() {
    /* * 讀取 I2C 控制狀態暫存器的最低位元 (bit 0)。
     * 如果最低位元為 1，代表硬體偵測到訊號線異常、超時或者是感測器沒接好。
     * 這就是專案驗證計畫中的「斷線防呆測試」判定點。
     */
    if (I2C_BUS0_CTRL_REG & 0x01) { 
        return ERROR_CODE; // 感測器訊號線異常，立即回傳錯誤代碼 0xFF
    }
    
    /*
     * 如果硬體狀態正常，則直接從資料暫存器 (I2C_BUS0_DATA_REG) 把傳輸完成的
     * 8 位元溫度整數數據讀出來，並透過 0xFF 進行位元遮罩 (Bit Mask)，確保資料乾淨。
     */
    int raw_data = I2C_BUS0_DATA_REG & 0xFF;
    return raw_data; // 傳回正確的環境溫度
}

/**
 * @brief 主程式進入點 (Main Loop)
 * @details 控制整台自動溫控風扇的最高指揮中心，負責初始化週邊、持續讀取溫度、
 * 執行邏輯判斷、並動態改寫轉速與螢幕顯示。
 */
int main() {
    // 1. 系統剛啟動，呼叫 LCD 初始化函數，設定好螢幕電路
    lcd_init();
    
    // 2. 將自製的 PWM 占空比暫存器清零，確保開機時風扇馬達是靜止的，維護硬體安全
    PWM_DUTY_REG = 0; 
    
    // 3. 在螢幕上打出開機初始畫面，提示使用者系統正在啟動中
    lcd_print_msg("System Init...");
    delay_ms(1000);      // 讓啟動畫面維持 1 秒鐘
    LCD_DATA_REG = 0x01; // 清空螢幕，準備進入主輪詢迴圈
    
    /* * 【主輪詢無限迴圈 (Main Polling Loop)】
     * 嵌入式系統不會停止運行，CPU 會在迴圈內永無止境地執行監測與控制。
     */
    while (1) {
        // 呼叫函數，透過 Memory-Mapped I/O 去向硬體要當前的溫度數據
        int temp = i2c_read_dht11_temp();
        
        // --- 核心邏輯判定分支 ---
        
        // 分支 A：防呆機制。如果讀到錯誤代碼，代表感測器被拔掉或壞了
        if (temp == ERROR_CODE) {
            LCD_DATA_REG = 0x01;       // 先清空螢幕上舊的殘留資訊
            lcd_print_msg("Temp: ERR!"); // 螢幕打出 ERR 警告，提醒使用者檢查線路
            PWM_DUTY_REG = 0;          // 為了硬體安全，強制將風扇馬達斷電歸零
        } 
        
        // 分支 B：智慧高溫監測。如果溫度大於或等於規定的 28 度門檻值
        else if (temp >= 28) {
            /* * 將 PWM 占空比暫存器直接寫入最大值 255 (100% Full Duty)。
             * 硬體 PWM 模組收到後，輸出腳位會維持長高電位，馬達驅動板就會全力供電，
             * 讓風扇瞬間切換到強風模式，達到快速降溫的效果。
             */
            PWM_DUTY_REG = 255;  
            LCD_DATA_REG = 0x01; // 清空舊畫面
            lcd_print_msg("Temp: High, FAN:ON"); // 更新螢幕狀態為強風模式
        } 
        
        // 分支 C：常溫舒適監測。如果溫度低於 28 度
        else {
            /*
             * 將 PWM 占空比暫存器寫入較低的數值 64 (約 25% Duty)。
             * 硬體脈衝寬度會變窄，輸出給馬達驅動板的平均電壓降低，
             * 風扇會自動降速運轉，保持在低速靜音省電模式。
             */
            PWM_DUTY_REG = 64;   
            LCD_DATA_REG = 0x01; // 清空舊畫面
            lcd_print_msg("Temp: Normal, FAN:LOW"); // 更新螢幕狀態為低速模式
        }
        
        // --- 輪詢頻率控制 ---
        // 根據 DHT11 溫濕度感測器的硬體元件規格，兩次讀取之間至少需要 2 秒的穩定時間。
        // 所以在迴圈最後強制延遲 2000 毫秒，避免過度頻繁讀取導致硬體晶片過熱或當機。
        delay_ms(2000); 
    }
    
    return 0; // 嵌入式系統理論上不會執行到這行
}
