library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all ;
use std.textio.all ;
package VhdlSimSet is

  -- SYSTEM ------------------------------------------------------------
  -- Clock generation --
  constant kClkPeriod : time:= 8 ns;

  procedure clock(signal clk : out std_logic);
  procedure nclocks(signal clk : out std_logic; ncycle : integer);

  -- Power-up process --
  constant kResetLength : integer:= 10;

  procedure release_reset(
    signal rst : out std_logic;
    signal clk : out std_logic
  );

  -- Signal --
  procedure set_signal_after(
    signal sig : out std_logic;
    signal clk : out std_logic;
           high_low  : in std_logic;
           n_clocks  : in integer
    );

  procedure wait_until(
    signal sig : in std_logic;
    signal clk : out std_logic;
           high_low  : in std_logic
    );

  function gen_biterror(
    data_in   : in std_logic_vector;
    enable    : in std_logic
    ) return std_logic_vector;


  -- Text IO -----------------------------------------------------------
  procedure skip_whitespace ( L : inout LINE );
  procedure read_str(
    l     : inout line;
    VALUE : out string;
    good  : out boolean;
--    i     : out integer
    i     : inout integer
    );

  function strcmp (A : STRING ; B : STRING) return boolean;


end package VhdlSimSet;

package body VhdlSimSet is

  -- Clock generation --------------------------------------------------
  procedure clock(signal clk : out std_logic) is
  begin
    clk   <= '0';
    wait for kClkPeriod/2;
    clk   <= '1';
    wait for kClkPeriod/2;
  end procedure;

  procedure nclocks(
    signal clk : out std_logic;
     ncycle : integer
     ) is
  begin
    for i in 0 to ncycle-1 loop
      clock(clk);
    end loop;
  end procedure;

  procedure release_reset(
    signal rst : out std_logic;
    signal clk : out std_logic
    ) is
  begin
    rst   <= '1';
    for i in 0 to kResetLength-1 loop
      clock(clk);
    end loop;
    rst   <= '0';
  end procedure;

  procedure set_signal_after(
     signal sig : out std_logic;
     signal clk : out std_logic;
            high_low  : in std_logic;
            n_clocks  : in integer
     ) is
  begin
    for i in 0 to n_clocks-1 loop
      clock(clk);
    end loop;
    sig   <= high_low;
  end procedure;

  procedure wait_until(
    signal sig : in std_logic;
    signal clk : out std_logic;
           high_low  : in std_logic
    ) is
  begin
    while true loop
      if(sig = high_low) then
        exit;
      end if;
      clock(clk);
    end loop;
  end procedure;

  function gen_biterror(
    data_in  : in  std_logic_vector;
    enable : in std_logic
   ) return std_logic_vector is
    variable inv_bit  : std_logic_vector(data_in'range) := (others => '0');
    variable data_out : std_logic_vector(data_in'range) := (others => '0');
  begin
    inv_bit(inv_bit'low)  := '1';
    if(enable = '1') then
      data_out  := data_in xor inv_bit;
    else
      data_out  := data_in;
    end if;

    return data_out;
  end function;


  -- Text IO -----------------------------------------------------------
  -- --
  procedure skip_whitespace( L : inout LINE ) is
    variable readOk : BOOLEAN;
    variable c : CHARACTER;
    constant NBSP : CHARACTER := CHARACTER'val(160);
  begin

    while L /= null and L.all'length /= 0 loop
      if (L.all(L'low) = ' ' or L.all(L'low) = NBSP or L.all(L'low) = ',' or L.all(L'low) = HT) then
        read (l, c, readOk);
      else
        exit;
      end if;
    end loop;
  end procedure;

  -- --
  procedure read_str(
    l     : inout line;
    VALUE : out string;
    good  : out boolean;
  --  i     : out integer
    i     : inout integer
    ) is
    variable c      : CHARACTER;
    variable readOk : BOOLEAN;
    --variable i      : INTEGER;
    constant NBSP   : CHARACTER      := CHARACTER'val(160);
  begin
    VALUE := (VALUE'range => 'U');
    Skip_whitespace (L);
    good := FALSE;
    if VALUE'length > 0 then
      read (l, c, readOk);
      i := value'low;

      while i >= VALUE'low loop
        if readOk = false then
         VALUE(i) := NUL;
         return;
        end if;

        if (c = ' ') or (c = HT) or (C = ',') or (c = NBSP) then
          VALUE(i) := NUL;
          return;
        end if;

        VALUE(i) := c;
        i := i + 1;
        good := TRUE;
        read(l, c, readOk);
      end loop;
    end if;
  end procedure;

  -- --
  function strcmp (A : STRING ; B : STRING) return boolean is
  begin
    for i in A'range loop
      if(A(i) = NUL) and ((i < B'low) or (i > B'high)) then
      --if(A(i) = NUL) then
        return true;
      else
        --report integer'image(i);-- & " " & A(i);
      end if;
      if((i < B'low) or (i > B'high)) then
        return false;
      end if;
      if (A(i) /= B(i)) then
        return false;
      end if;
    end loop;
  return true;
end function;

end package body VhdlSimSet;
