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
        sysClk          :   in  std_logic;
        adcClk          :   in  std_logic;
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
        adcData_i       :   in  std_logic_vector(31 downto 0);
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
signal regs :   t_param_reg_array(3 downto 0);

begin
--
-- PLL outputs
--
pll_hi_o <= '0';
pll_lo_o <= '1';
--
-- DAC Outputs
--
dac_a_o <= not(std_logic_vector(resize(signed(regs(1)(15 downto 0)),dac_a_o'length)));
dac_b_o <= not(std_logic_vector(resize(signed(regs(1)(31 downto 16)),dac_b_o'length)));
dac_reset_o <= not(aresetn);
ext_o <= regs(0)(7 downto 0);

--
-- AXI communication routing - connects bus objects to std_logic signals
--
bus_m.addr <= addr_i;
bus_m.valid <= dataValid_i;
bus_m.data <= writeData_i;
readData_o <= bus_s.data;
resp_o <= bus_s.resp;

Parse: process(sysClk,aresetn) is
begin
    if aresetn = '0' then
        comState <= idle;
        reset <= '0';
        bus_s <= INIT_AXI_BUS_SLAVE;
        regs <= (others => (others => '0'));
        
    elsif rising_edge(sysClk) then
        FSM: case(comState) is
            when idle =>
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
                            when X"000000" => rw(bus_m,bus_s,comState,regs(0));  
                            when X"000004" => rw(bus_m,bus_s,comState,regs(1));
                            when X"000008" => rw(bus_m,bus_s,comState,regs(2));
                            when X"00000C" => rw(bus_m,bus_s,comState,regs(3));

                            
                            when others => 
                                comState <= finishing;
                                bus_s.resp <= "11";
                        end case;
                    
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