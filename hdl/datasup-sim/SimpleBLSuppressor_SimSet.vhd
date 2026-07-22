library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use std.textio.all;

library mylib;
use mylib.defYaenamiAdc.all;
use mylib.defADC.all;

use work.VhdlSimSet.all;
use work.SimpleBLSuppressor_SimSet.all;

entity SimpleBLSuppressor_TB is
end SimpleBLSuppressor_TB;

architecture Behavioral of SimpleBLSuppressor_TB is

  constant kNumSample   : integer := 4;
  constant kWidthData   : integer := 10;


  signal clk          : std_logic;
  signal srst         : std_logic;
  signal validIn      : std_logic;
  signal dIn          : std_logic_vector(kNumSample*kWidthData-1 downto 0);
  signal validOut     : std_logic;
  signal dOut         : std_logic_vector(kNumSample*kWidthData-1 downto 0);
  signal typeOut      : std_logic_vector(kWidthAdcSFType-1 downto 0);

  file in_file        : text;

begin


  main : process
  begin
 
    srst <= '1';
    for i in 1 to 10 loop clock(clk); end loop;
    srst <= '0';
    for i in 1 to 2 loop clock(clk); end loop;

   
    file_open(in_file, "C:/Vivado_Projects/test_pattern.txt", READ_MODE);
    set_txt(in_file, clk, dIn, validIn);
    file_close(in_file);


    for i in 1 to 10 loop clock(clk); end loop;
    std.env.stop;
  end process;

  u_dut : entity mylib.SimpleBLSuppressor
    generic map(
      kNumSample      => kNumSample,
      kWidthAdcData   => kWidthData,
      kNumFsModeWords => 256,
      enDEBUG         => false
    )
    port map(
      srst        => srst,
      clk         => clk,
      enUnit      => '1',
      polarityIn  => '1',
      thresholdIn => std_logic_vector(to_unsigned(100, kWidthData)),
      validIn     => validIn,
      dIn         => dIn,
      validOut    => validOut,
      dOut        => dOut,
      typeOut     => typeOut
    );

end Behavioral;