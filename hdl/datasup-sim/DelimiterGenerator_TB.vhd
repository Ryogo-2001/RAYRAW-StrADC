-- File: DelimiterGenerator_TB.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defDelimiter.all;
use mylib.defLaccp.all;

entity DelimiterGenerator_TB is
end DelimiterGenerator_TB;

architecture Behavioral of DelimiterGenerator_TB is

  constant kClkPeriod : time := 10 ns;

  signal syncReset       : std_logic := '0';
  signal clk             : std_logic := '0';
  
  -- set in
  signal flagsIn         : std_logic_vector(kWidthDelimiterFlag-1 downto 0) := (others => '0');
  signal hbfNumber       : std_logic_vector(kWidthStrHbf-1 downto 0) := (others => '0');
  signal signBit         : std_logic := '0';

  -- hbCount
  signal hbCount         : std_logic_vector(kWidthStrHbc-1 downto 0) := (others => '0');
  
  -- d out
  signal validDelimiter  : std_logic;
  signal dOutDelimiter   : std_logic_vector(kWidthData-1 downto 0);

  -- 16bit count
  signal tb_hb_counter   : unsigned(15 downto 0) := (others => '0');

begin

  -- generate clk
  p_clk : process
  begin
    clk <= '0'; wait for kClkPeriod/2;
    clk <= '1'; wait for kClkPeriod/2;
  end process;

  -- DUT
  u_dut : entity work.DelimiterGenerator
    generic map (
      enDEBUG => false
    )
    port map (
      syncReset      => syncReset,
      clk            => clk,
      flagsIn        => flagsIn,
      hbCount        => hbCount,
      hbfNumber      => hbfNumber,
      signBit        => signBit,
      validDelimiter => validDelimiter,
      dOutDelimiter  => dOutDelimiter
    );
  
  -- hbCount : roop kMaxHBCount -> 0 ->kMaxHBCount ->0
  p_counter : process(clk)
  begin
    --if rising_edge(clk) then
    if falling_edge(clk) then
      if syncReset = '1' then
        -- start 0
        -- tb_hb_counter <= (others => '0');

        -- Start from the value XX less than kMaxHBCount.
        tb_hb_counter <= unsigned(kMaxHBCount) - 10;

      else
        -- if kMaxHBCount -> 0 reset
        if tb_hb_counter = unsigned(kMaxHBCount) then
          tb_hb_counter <= (others => '0');
        else
          -- count up
          tb_hb_counter <= tb_hb_counter + 1;
        end if;
      end if;
    end if;
  end process;

  hbCount <= std_logic_vector(tb_hb_counter);


  -- main
  p_stimulus : process
  begin
    syncReset <= '1';
    wait for kClkPeriod * 10;
    syncReset <= '0';
    
    -- hbfNumber
    hbfNumber <= std_logic_vector(to_unsigned(1, kWidthStrHbf));
    
    -- kMaxHBCount 
    wait for kClkPeriod * 70000;

    std.env.stop;
  end process;

end Behavioral;