library IEEE;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.ALL;
use ieee.std_logic_unsigned.all; 
use work.CustomDataTypes.all;
use work.AXI_Bus_Package.all;

--
-- Example top-level module for parsing simple AXI instructions
--
entity topmod is
    port (
        --
        -- Clocks and reset
        --
        sysclk          :   in  std_logic_vector(2 downto 0);
        adcclk          :   in  std_logic_vector(2 downto 0);
        aresetn         :   in  std_logic;
        --
        -- AXI-super-lite signals
        --      
        addr_i          :   in  unsigned(AXI_ADDR_WIDTH-1 downto 0);            --Address out
        writeData_i     :   in  std_logic_vector(AXI_DATA_WIDTH-1 downto 0);    --Data to write
        dataValid_i     :   in  std_logic_vector(1 downto 0);                   --Data valid out signal
        readData_o      :   out std_logic_vector(AXI_DATA_WIDTH-1 downto 0);    --Data to read
        resp_o          :   out std_logic_vector(1 downto 0);                   --Response in
        --
        -- External I/O
        --
        ext_i           :   in  std_logic_vector(7 downto 0);
        ext_o           :   out std_logic_vector(7 downto 0);
        --
        -- PLL outputs
        --
        pll_hi_o        :   out std_logic;
        pll_lo_o        :   out std_logic;
        --
        -- ADC data
        --
        adc_dat_a_i     :   in  std_logic_vector(13 downto 0);
        adc_dat_b_i     :   in  std_logic_vector(13 downto 0);
        adc_sync_o      :   out std_logic;
        idly_rst_o      :   out std_logic;
        --
        -- DAC data
        --
        dac_a_o         :   out std_logic_vector(DAC_WIDTH - 1 downto 0);
        dac_b_o         :   out std_logic_vector(DAC_WIDTH - 1 downto 0);
        dac_reset_o     :   out std_logic
        
    );
end topmod;


architecture Behavioural of topmod is

--ATTRIBUTE X_INTERFACE_INFO : STRING;
--ATTRIBUTE X_INTERFACE_INFO of m_axis_tdata: SIGNAL is "xilinx.com:interface:axis:1.0 m_axis TDATA";
--ATTRIBUTE X_INTERFACE_INFO of m_axis_tvalid: SIGNAL is "xilinx.com:interface:axis:1.0 m_axis TVALID";
--ATTRIBUTE X_INTERFACE_PARAMETER : STRING;
--ATTRIBUTE X_INTERFACE_PARAMETER of m_axis_tdata: SIGNAL is "CLK_DOMAIN system_processing_system7_0_0_FCLK_CLK0,FREQ_HZ 125000000";
--ATTRIBUTE X_INTERFACE_PARAMETER of m_axis_tvalid: SIGNAL is "CLK_DOMAIN system_processing_system7_0_0_FCLK_CLK0,FREQ_HZ 125000000";

COMPONENT DDS_Output
  PORT (
    aclk : IN STD_LOGIC;
    aresetn : IN STD_LOGIC;
    s_axis_phase_tvalid : IN STD_LOGIC;
    s_axis_phase_tdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    m_axis_data_tvalid : OUT STD_LOGIC;
    m_axis_data_tdata : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
  );
END COMPONENT;

component SaveADCData is
    port(
        readClk     :   in  std_logic;          --Clock for reading data
        writeClk    :   in  std_logic;          --Clock for writing data
        aresetn     :   in  std_logic;          --Asynchronous reset
        
        data_i      :   in  std_logic_vector;   --Input data, maximum length of 32 bits
        valid_i     :   in  std_logic;          --High for one clock cycle when data_i is valid
        
        numSamples  :   in  t_mem_addr;         --Number of samples to save
        trig_i      :   in  std_logic;          --Start trigger
        
        bus_m       :   in  t_mem_bus_master;   --Master memory bus
        bus_s       :   out t_mem_bus_slave     --Slave memory bus
    );
end component;


--
-- AXI communication signals
--
signal comState             :   t_status                        :=  idle;
signal bus_m                :   t_axi_bus_master                :=  INIT_AXI_BUS_MASTER;
signal bus_s                :   t_axi_bus_slave                 :=  INIT_AXI_BUS_SLAVE;
signal reset                :   std_logic;
--
-- Registers
--
signal triggers :   t_param_reg;
signal regs     :   t_param_reg_array(3 downto 0);
--
-- ADC data
--
signal adc      :   t_adc_array;
signal adcReg   :   t_param_reg;
--
-- DAC signals
--
signal dds_a, dds_b :   std_logic_vector(15 downto 0);
signal dac_a, dac_b :   signed(DAC_WIDTH - 1 downto 0);
--
-- Memory signals
--
signal memData_i        :   t_mem_data;
signal memDataValid_i   :   std_logic;
signal mem_bus          :   t_mem_bus;
signal numSamples       :   t_mem_addr;
signal memtrig          :   std_logic;

begin
--
-- PLL outputs
--
pll_hi_o <= '0';
pll_lo_o <= '1';
--
-- Generate some DDS values
--
DDS_OUTPUT_A: DDS_Output
port map(
    aclk                =>  adcclk(1),
    aresetn             =>  aresetn,
    s_axis_phase_tvalid =>  '1',
    s_axis_phase_tdata  =>  regs(2),
    m_axis_data_tvalid  =>  open,
    m_axis_data_tdata   =>  dds_a
);

DDS_OUTPUT_B: DDS_Output
port map(
    aclk                =>  adcclk(1),
    aresetn             =>  aresetn,
    s_axis_phase_tvalid =>  '1',
    s_axis_phase_tdata  =>  regs(3),
    m_axis_data_tvalid  =>  open,
    m_axis_data_tdata   =>  dds_b
);
--
-- Choose between DC values or the DDS outputs
--
dac_a <= resize(signed(regs(1)(15 downto 0)),DAC_WIDTH) when regs(0)(8) = '0' else shift_left(resize(signed(dds_a),DAC_WIDTH),4);
dac_b <= resize(signed(regs(1)(31 downto 16)),DAC_WIDTH) when regs(0)(9) = '0' else shift_left(resize(signed(dds_b),DAC_WIDTH),4);
--
-- This makes sure that the output values are synchronous with the ADC clock,
-- which is necessary to reduce harmonic content in the output voltages
--
DAC_Process: process(adcclk(1),aresetn) is
begin
    if aresetn = '0' then
        dac_a_o <= (others => '1');
        dac_b_o <= (others => '1');
    elsif rising_edge(adcclk(1)) then
        dac_a_o <= not(std_logic_vector(dac_a));
        dac_b_o <= not(std_logic_vector(dac_b));
    end if;
end process;

dac_reset_o <= not(aresetn);
ext_o <= regs(0)(7 downto 0);
idly_rst_o <= regs(0)(10);
--
-- ADC data
--
adc(0) <= resize(signed(adc_dat_b_i),16);
adc(1) <= resize(signed(adc_dat_a_i),16);
adcReg <= std_logic_vector(adc(1)) & std_logic_vector(adc(0));
adc_sync_o <= 'Z';
--
-- Save ADC data
--
memData_i <= std_logic_vector(adc(1)) & std_logic_vector(adc(0));
memDataValid_i <= '1';
memTrig <= triggers(0);
SaveData: SaveADCData
port map(
    readClk     =>  sysclk(0),
    writeClk    =>  adcclk(1),
    aresetn     =>  aresetn,
    data_i      =>  memData_i,
    valid_i     =>  memDataValid_i,
    numSamples  =>  numSamples,
    trig_i      =>  memTrig,
    bus_m       =>  mem_bus.m,
    bus_s       =>  mem_bus.s  
);
--
-- AXI communication routing - connects bus objects to std_logic signals
--
bus_m.addr <= addr_i;
bus_m.valid <= dataValid_i;
bus_m.data <= writeData_i;
readData_o <= bus_s.data;
resp_o <= bus_s.resp;

Parse: process(sysclk(0),aresetn) is
begin
    if aresetn = '0' then
        comState <= idle;
        reset <= '0';
        bus_s <= INIT_AXI_BUS_SLAVE;
        regs <= (others => (others => '0'));
        triggers <= (others => '0');
        mem_bus.m <= INIT_MEM_BUS_MASTER;
        
        
    elsif rising_edge(sysclk(0)) then
        FSM: case(comState) is
            when idle =>
                triggers <= (others => '0');
                reset <= '0';
                bus_s.resp <= "00";
                if bus_m.valid(0) = '1' then
                    comState <= processing;
                end if;

            when processing =>
                AddrCase: case(bus_m.addr(31 downto 24)) is
                    --
                    -- Parameter parsing
                    --
                    when X"00" =>
                        ParamCase: case(bus_m.addr(23 downto 0)) is
                            --
                            -- This issues a reset signal to the memories and writes data to
                            -- the trigger registers
                            --
                            when X"000000" => rw(bus_m,bus_s,comState,triggers);
                            when X"000004" => rw(bus_m,bus_s,comState,regs(0));  
                            when X"000008" => rw(bus_m,bus_s,comState,regs(1));
                            when X"00000C" => rw(bus_m,bus_s,comState,regs(2));
                            when X"000010" => rw(bus_m,bus_s,comState,regs(3));
                            when X"000014" => readOnly(bus_m,bus_s,comState,adcReg);
                            when X"000018" => rw(bus_m,bus_s,comState,numSamples);
                            when X"00001C" => readOnly(bus_m,bus_s,comState,mem_bus.s.last);

                            
                            when others => 
                                comState <= finishing;
                                bus_s.resp <= "11";
                        end case;
                        
                    --
                    -- Retrieve data from memory
                    --
                    when X"01" =>
                        if bus_m.valid(1) = '0' then
                            bus_s.resp <= "11";
                            comState <= finishing;
                            mem_bus.m.trig <= '0';
                            mem_bus.m.status <= idle;
                        elsif mem_bus.s.valid = '1' then
                            bus_s.data <= mem_bus.s.data;
                            comState <= finishing;
                            bus_s.resp <= "01";
                            mem_bus.m.status <= idle;
                            mem_bus.m.trig <= '0';
                        elsif mem_bus.s.status = idle then
                            mem_bus.m.addr <= bus_m.addr(MEM_ADDR_WIDTH + 1 downto 2);
                            mem_bus.m.status <= waiting;
                            mem_bus.m.trig <= '1';
                         else
                            mem_bus.m.trig <= '0';
                        end if;
                    
                    when others => 
                        comState <= finishing;
                        bus_s.resp <= "11";
                end case;
            when finishing =>
--                triggers <= (others => '0');
--                reset <= '0';
                comState <= idle;

            when others => comState <= idle;
        end case;
    end if;
end process;

    
end architecture Behavioural;