library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.VhdlSimSet.all;

package SimpleBLSuppressor_SimSet is
   
    constant kNumSample : integer := 4;
    constant kWidthData : integer := 10;

    procedure set_txt(
        file in_file     : text;
        signal clk       : out std_logic;
        signal dIn       : out std_logic_vector(kNumSample*kWidthData-1 downto 0);
        signal validIn   : out std_logic
    );
end package;

package body SimpleBLSuppressor_SimSet is
    procedure set_txt(
        file in_file     : text;
        signal clk       : out std_logic;
        signal dIn       : out std_logic_vector(kNumSample*kWidthData-1 downto 0);
        signal validIn   : out std_logic
    ) is
        variable l       : line;
        variable token   : string(1 to 16);
        variable good    : boolean;
        variable i       : integer;
        variable p_count : integer;
        variable v_s0, v_s1, v_s2 : integer;
    begin
        validIn <= '0';
        dIn     <= (others => '0');

        while (not endfile(in_file)) loop
            readline(in_file, l);

           
            if l = null or l.all'length = 0 or l.all(1) = '#' then
                next;
            end if;

           
            read_str(l, token, good, i);

            if strcmp(token, "SEND") then
               
                read(l, v_s0);
                read(l, v_s1);
                read(l, v_s2);

               
                dIn(  kWidthData-1 downto           0) <= std_logic_vector(to_unsigned(v_s0, kWidthData));
                dIn(2*kWidthData-1 downto   kWidthData) <= std_logic_vector(to_unsigned(v_s1, kWidthData));
                dIn(3*kWidthData-1 downto 2*kWidthData) <= std_logic_vector(to_unsigned(v_s2, kWidthData));
                dIn(4*kWidthData-1 downto 3*kWidthData) <= (others => '0');
                validIn <= '1';

               
                clock(clk); 

               
                dIn     <= (others => '0');
                validIn <= '0';

            elsif strcmp(token, "PAUSE") then
                               read_str(l, token, good, i);
                p_count := integer'value(token(1 to i-1));
                for j in 1 to p_count loop
                    clock(clk); 
                end loop;

            elsif strcmp(token, "END") then
               
                exit;
            end if;
        end loop;
    end procedure;
end package body;
