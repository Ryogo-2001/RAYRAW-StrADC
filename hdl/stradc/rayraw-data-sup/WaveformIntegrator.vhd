-- File: WaveformIntegrator.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;

entity WaveformIntegrator is
  generic (
    kNumSample     : integer := 4;
    kWidthAdcData  : integer := 10;
    kWidthIntegral : integer := 32;
    kValidNumSample : integer := 3
  );
  port (
    clk            : in  std_logic;
    srst           : in  std_logic;

    -- beseline in
    baselineIn     : in  std_logic_vector(kWidthAdcData-1 downto 0);

    -- Data In --
    validIn        : in  std_logic;
    dIn            : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    typeIn         : in  std_logic_vector(kWidthAdcSFType-1 downto 0);

    -- Data Out --
    validOut       : out std_logic;
    integralOut    : out std_logic_vector(kWidthIntegral-1 downto 0)
  );
end WaveformIntegrator;

architecture Behavioral of WaveformIntegrator is

  type IntDataArray is array (0 to kNumSample-1) of unsigned(kWidthAdcData-1 downto 0);
  signal adc_data : IntDataArray;

  signal reg_integral : signed(kWidthIntegral-1 downto 0) := (others => '0');

begin

  gen_unpack : for i in 0 to kNumSample-1 generate
    adc_data(i) <= unsigned(dIn((i+1)*kWidthAdcData-1 downto i*kWidthAdcData));
  end generate;

  u_calc : process(clk)
    variable var_sum      : signed(kWidthIntegral-1 downto 0);
    variable var_baseline : signed(kWidthIntegral-1 downto 0);
  begin
    if rising_edge(clk) then
      if srst = '1' then
        reg_integral <= (others => '0');
        validOut     <= '0';
        integralOut  <= (others => '0');
      else
        validOut <= '0';

        if validIn = '1' then
          if typeIn = kCTypeSfHead then
            reg_integral <= (others => '0');

          elsif typeIn = kCTypeSfPayload then
            var_sum := (others => '0');
            var_baseline := resize(signed('0' & baselineIn), kWidthIntegral);

            for i in 0 to kValidNumSample-1 loop
              var_sum := var_sum + resize(signed('0' & adc_data(i)), kWidthIntegral) - var_baseline;
            end loop;
            
            reg_integral <= reg_integral + var_sum;

          elsif typeIn = kCTypeSfTrail then
            integralOut <= std_logic_vector(reg_integral);
            validOut    <= '1'; 
          end if;
        end if;
      end if;
    end if;
  end process;

end Behavioral;