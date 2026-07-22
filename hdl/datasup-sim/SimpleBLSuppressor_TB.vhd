library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
library mylib;
use mylib.defYaenamiAdc.all;
use mylib.defADC.all;

entity SimpleBLSuppressor_TB is
end SimpleBLSuppressor_TB;

architecture Behavioral of SimpleBLSuppressor_TB is

  constant kClkPeriod   : time    := 8000 ps;   -- 125 MHz
  constant kNumSample   : integer := 4;
  constant kWidthData   : integer := 10;  -- AdcBit

  signal clk          : std_logic := '0';
  signal srst         : std_logic := '1';
  signal validIn      : std_logic := '0';
  signal dIn          : std_logic_vector(kNumSample*kWidthData-1 downto 0) := (others => '0');
  signal validOut     : std_logic;
  signal dOut         : std_logic_vector(kNumSample*kWidthData-1 downto 0);
  signal typeOut      : std_logic_vector(kWidthAdcSFType-1 downto 0);

  procedure SendSamples(
    s0, s1, s2     : in integer;
    signal dIn     : out std_logic_vector(kNumSample*kWidthData-1 downto 0);
    signal validIn : out std_logic
  ) is
  begin
    dIn(  kWidthData-1 downto           0) <= std_logic_vector(to_unsigned(s0, kWidthData));
    dIn(2*kWidthData-1 downto   kWidthData) <= std_logic_vector(to_unsigned(s1, kWidthData));
    dIn(3*kWidthData-1 downto 2*kWidthData) <= std_logic_vector(to_unsigned(s2, kWidthData));
    dIn(4*kWidthData-1 downto 3*kWidthData) <= (others => '0');  -- unused, always 0
    validIn <= '1';
    wait for 8000 ps;
    dIn     <= (others => '0');
    validIn <= '0';
    wait for 8000 ps * 4;
  end procedure;

begin

  clk <= not clk after kClkPeriod / 2;

  u_dut : entity mylib.SimpleBLSuppressor
-- u_dut : entity mylib.BLSuppressor_a
    generic map(
      kNumSample      => kNumSample,
      kWidthAdcData   => kWidthData,
      kNumFsModeWords => 256,
      enDEBUG         => false
    )
    port map(
      srst        => srst,
      clk         => clk,
      enUnit      => '1',                                          -- BL suppression on
      polarityIn  => '1',                                          -- positive 
      thresholdIn => std_logic_vector(to_unsigned(100, kWidthData)), -- threshold
      validIn     => validIn,
      dIn         => dIn,
      validOut    => validOut,
      dOut        => dOut,
      typeOut     => typeOut
    );

  process
  begin
    -- Reset
    srst    <= '1';
    validIn <= '0';
    dIn     <= (others => '0');
    --wait for kClkPeriod * 4;
    wait for kClkPeriod * 8;
    srst    <= '0';
    wait for kClkPeriod * 2;

    SendSamples(30, 60, 40, dIn, validIn);
    SendSamples(43, 60, 25, dIn, validIn);
    SendSamples(20, 50, 70, dIn, validIn);    
    SendSamples(50, 60, 70, dIn, validIn);
    SendSamples(200, 300, 400, dIn, validIn);
    SendSamples(600, 700, 800, dIn, validIn);
    SendSamples(60, 700, 800, dIn, validIn);
    SendSamples(50, 60, 70, dIn, validIn);
    SendSamples(30, 60, 40, dIn, validIn);
    SendSamples(43, 60, 25, dIn, validIn);
    SendSamples(20, 50, 70, dIn, validIn);
    SendSamples(50, 60, 70, dIn, validIn);
    SendSamples(30, 60, 40, dIn, validIn);
    SendSamples(43, 60, 25, dIn, validIn);
    SendSamples(20, 50, 70, dIn, validIn);
    SendSamples(50, 60, 70, dIn, validIn);
    SendSamples(200, 300, 400, dIn, validIn);
    SendSamples(600, 700, 800, dIn, validIn);
    SendSamples(50, 60, 70, dIn, validIn);
    SendSamples(50, 50, 50, dIn, validIn);

    wait for kClkPeriod * 8;
    wait;
  end process;

end Behavioral;