# ============================================================================
# 元智大學 114-2 數位系統設計與實驗 期末專題
# 學號: 1120845 
# 姓名: 余洺錩
# 
# 檔案名稱: sw/Makefile
# 功能說明: 
#   自動化編譯建構腳本。負責呼叫跨平台編譯工具鏈 (Cross-compiler Toolchain)，
#   將 main.c 原始碼編譯、超連結、並轉換為 FPGA 內 Instruction Memory 
#   (唯讀區塊記憶體 BRAM) 在合成時可以直接讀取載入的 .mem 十六進位初始化檔案。
# ============================================================================

# 定義最終要產生的主檔名目標
TARGET = main

# 定義跨平台編譯器的前綴字 (Prefix)
# 因為我們是在 x86/ARM 的電腦上開發，但目標是要編譯給 FPGA 裡面的 RISC-V CPU 執行
# 所以必須使用跨平台工具鏈：riscv32-unknown-elf-
CROSS_COMPILE = riscv32-unknown-elf-
CC = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy

# 定義編譯器的優化標籤與架構設定
# -march=rv32i: 指定目標 CPU 為基礎的 32位元 RISC-V 整數指令集 (不含硬體乘除法，簡化硬體)
# -mabi=ilp32: 指定標準的 32位元整數、長整數與指標的應用程式二進位介面 (ABI)
# -O1: 開啟一級優化，既能精簡程式碼體積，又不會破壞我們寫的軟體延遲迴圈邏輯
# -nostdlib: 告訴編譯器不要包含標準 C 語言函式庫 (因為 FPGA 裡面沒有作業系統，不支援 printf 等)
CFLAGS = -march=rv32i -mabi=ilp32 -O1 -nostdlib

# 預設建構目標：最終生出 Vivado 看得懂的 .mem 檔案
all: $(TARGET).mem

# 步驟 1：將 main.c 編譯並超連結成 ELF 執行檔
# -Ttext 0x00000000: 極為關鍵！指定軟體程式碼的起跑點 (Entry Point) 位於記憶體位址 0。
# 這樣硬體重置放開後，CPU 才會準確去位址 0 抓第一條指令執行。
$(TARGET).elf: main.c
	$(CC) $(CFLAGS) -Ttext 0x00000000 -o $(TARGET).elf main.c

# 步驟 2：利用 objcopy 工具，把 ELF 檔案中多餘的除錯資訊與標頭拔掉，轉換成純粹的二進位機器碼 (Binary)
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $(TARGET).elf $(TARGET).bin

# 步驟 3：將二進位純機器碼轉換成 Vivado 硬體可相容的 Hex 記憶體初始化格式 (.mem)
# hexdump 工具會把 binary 每 4 個位元組 (32-bit 一條指令) 轉成一筆 16 進位文字，並自動換行。
# 產生的 main.mem 檔案可以直接被 Vivado 的 $readmemh 指令載入。
$(TARGET).mem: $(TARGET).bin
	hexdump -v -e '1/4 "%08x\n"' $(TARGET).bin > $(TARGET).mem

# 清除建構過程中產生的所有暫存檔與成品，恢復乾淨資料夾
clean:
	rm -f *.elf *.bin *.mem
