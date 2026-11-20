-- File: DataSelector.vhd
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library mylib;
use mylib.defDataBusAbst.all;
use mylib.defADC.all;
use mylib.defDelimiter.all;

entity DataSelector is
  generic (
    kNumSample     : integer := 4;
    kWidthAdcData  : integer := 10;
    kWidthIntegral : integer := 32;
    kMaxBufWords   : integer := 256;
    kPreSamples    : integer range 1 to 15 := 2;
    kClkPerWord    : integer range 1 to 64 := 5
  );
  port (
    clk            : in  std_logic;
    srst           : in  std_logic;

    -- data in (ADC)
    raw_validIn    : in  std_logic;
    raw_dIn        : in  std_logic_vector(kNumSample*kWidthAdcData-1 downto 0);
    raw_typeIn     : in  std_logic_vector(kWidthAdcSFType-1 downto 0);

    -- data in 
    intg_val       : in  std_logic_vector(kWidthIntegral-1 downto 0);
    peak_val       : in  std_logic_vector(kWidthAdcData-1 downto 0);
    tot_val        : in  std_logic_vector(kWidthIntegral-1 downto 0);
    isSat          : in  std_logic;
    isPileup       : in  std_logic;
    pileup_valid   : in  std_logic;

    -- HBD in (64bit)
    validDelimiter : in  std_logic;
    dInDelimiter   : in  std_logic_vector(63 downto 0);

    -- Data out
    validOut       : out std_logic;
    dOut           : out std_logic_vector(63 downto 0)
  );
end DataSelector;

architecture Behavioral of DataSelector is

  constant kWidthBus : integer := kNumSample * kWidthAdcData;

  -- memory
  type t_data_buf is array (0 to kMaxBufWords-1) of std_logic_vector(kWidthBus-1 downto 0);
  type t_type_buf is array (0 to kMaxBufWords-1) of std_logic_vector(kWidthAdcSFType-1 downto 0);

  signal buf_d : t_data_buf;
  signal buf_t : t_type_buf;

  attribute ram_style : string;
  attribute ram_style of buf_d : signal is "block";
  attribute ram_style of buf_t : signal is "block";

  -- registered read-back of buf_d/buf_t (1 cycle behind rd_ptr, matches Block RAM's synchronous-read latency)
  signal buf_d_q     : std_logic_vector(kWidthBus-1 downto 0);
  signal buf_t_q     : std_logic_vector(kWidthAdcSFType-1 downto 0);
  signal out_active  : std_logic := '0';  -- '1' when buf_d_q/buf_t_q hold a valid RAW word to output this cycle

  signal wr_ptr : integer range 0 to kMaxBufWords-1 := 0;
  signal rd_ptr : integer range 0 to kMaxBufWords-1 := 0;

  signal busy_event : std_logic := '0'; -- add flag (HBD)
  signal busy_raw   : std_logic := '0';
  signal req_raw    : std_logic := '0';
  signal req_sum    : std_logic := '0';
  signal req_hbd    : std_logic := '0';
  
  signal sum_step   : std_logic := '0';
  signal hbd_step   : std_logic := '0';

  -- regester
  signal reg_intg     : std_logic_vector(kWidthIntegral-1 downto 0);
  signal reg_peak     : std_logic_vector(kWidthAdcData-1 downto 0);
  signal reg_tot      : std_logic_vector(kWidthIntegral-1 downto 0);
  signal reg_hbd_data : std_logic_vector(63 downto 0);
  
  -- event counter
  signal num_word     : unsigned(15 downto 0) := (others => '0');

  -- HBD delay
  constant kHbdDelay : integer := kPreSamples * kClkPerWord + 2;
  signal valid_shift : std_logic_vector(kHbdDelay-1 downto 0) := (others => '0');
  type t_data_shift is array (0 to kHbdDelay-1) of std_logic_vector(63 downto 0);
  signal data_shift  : t_data_shift := (others => (others => '0'));

begin

  -- HBD delay process
  u_hbd_delay : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        valid_shift <= (others => '0');
        data_shift  <= (others => (others => '0'));
      else
        valid_shift(0) <= validDelimiter;
        data_shift(0)  <= dInDelimiter;
        -- shift process
        for i in 1 to kHbdDelay-1 loop
          valid_shift(i) <= valid_shift(i-1);
          data_shift(i)  <= data_shift(i-1);
        end loop;
      end if;
    end if;
  end process;


  -- Buffer
  u_write : process(clk)
    variable v_wr_addr : integer range 0 to kMaxBufWords-1;
  begin
    if rising_edge(clk) then
      if raw_validIn = '1' then
        if raw_typeIn = kCTypeSfHead then
          v_wr_addr := 0;
          wr_ptr    <= 1;
        else
          v_wr_addr := wr_ptr;
          wr_ptr    <= wr_ptr + 1;
        end if;

        -- single indexed write statement per array, so the tool can infer a proper
        -- single write port (a literal/variable split across two statements defeats it)
        buf_d(v_wr_addr) <= raw_dIn;
        buf_t(v_wr_addr) <= raw_typeIn;
      end if;
    end if;
  end process;

  -- Block RAM read port: address (rd_ptr) presented this cycle, data available next cycle.
  u_buf_read : process(clk)
  begin
    if rising_edge(clk) then
      buf_d_q <= buf_d(rd_ptr);
      buf_t_q <= buf_t(rd_ptr);
    end if;
  end process;

  u_read : process(clk)
  begin
    if rising_edge(clk) then
      if srst = '1' then
        busy_event   <= '0';
        busy_raw     <= '0';
        req_raw      <= '0';
        req_sum      <= '0';
        req_hbd      <= '0';
        sum_step     <= '0';
        hbd_step     <= '0';
        validOut     <= '0';
        rd_ptr       <= 0;
        out_active   <= '0';
        num_word     <= (others => '0');
      else
        
        if raw_validIn = '1' and raw_typeIn = kCTypeSfHead then
          busy_event <= '1';
        end if;

        
        if pileup_valid = '1' then
          if (isSat = '1') or (isPileup = '1') then
            req_raw <= '1';
          else
            req_sum <= '1';
          end if;
          reg_intg <= intg_val;
          reg_peak <= peak_val;
          reg_tot  <= tot_val;
        end if;

        -- ref kHbdDelay-1
        if valid_shift(kHbdDelay-1) = '1' then
          if req_hbd = '0' then
            reg_hbd_data <= data_shift(kHbdDelay-1); 
          end if;
          req_hbd <= '1';
        end if;


        validOut <= '0'; 

        -- RAW (buf_d/buf_t are Block RAM now: rd_ptr is the address issued *this*
        -- cycle, buf_d_q/buf_t_q hold the word for the address issued *last* cycle)
        if busy_raw = '1' or req_raw = '1' then

          if req_raw = '1' then
            -- burst start: issue the first address (0); no data ready yet this cycle
            req_raw    <= '0';
            busy_raw   <= '1';
            num_word   <= num_word + 1;
            out_active <= '0';
          else
            if out_active = '1' and buf_t_q = kCTypeSfTrail then
              -- the word we just received was the trailer: stop, no further address
              busy_raw   <= '0';
              busy_event <= '0';
              out_active <= '0';
              rd_ptr     <= 0;
            else
              -- keep issuing addresses; output becomes active one cycle after busy_raw
              rd_ptr     <= rd_ptr + 1;
              out_active <= busy_raw;
            end if;
          end if;

          if out_active = '1' then
            validOut <= '1';
            dOut(63 downto 60) <= "00" & buf_t_q;
            dOut(59 downto 40) <= (others => '0');
            dOut(39 downto 0)  <= buf_d_q;
          end if;

        elsif req_sum = '1' then
          validOut <= '1';
          
          if sum_step = '0' then
            dOut(63 downto 60) <= "00" & kCTypeSfPayload;
            dOut(59 downto 40) <= (others => '0');
            dOut(39 downto 0)  <= reg_intg & x"00";
            sum_step <= '1';
            num_word <= num_word + 1;
          else
            dOut(63 downto 60) <= "00" & kCTypeSfTrail;
            dOut(59 downto 40) <= (others => '0');
            dOut(39 downto 0)  <= reg_tot(29 downto 0) & reg_peak;
            sum_step   <= '0';
            req_sum    <= '0';
            busy_event <= '0'; 
          end if;

        -- HBD
        elsif req_hbd = '1' and (busy_event = '0' or hbd_step = '1') then
          validOut <= '1';
          
          if hbd_step = '0' then
            dOut     <= reg_hbd_data;
            hbd_step <= '1';
          else
            dOut(63 downto 58) <= kDatatypeHeartbeatT2;
            dOut(57 downto 16) <= (others => '0');
            dOut(15 downto 0)  <= std_logic_vector(num_word);
            hbd_step <= '0';
            req_hbd  <= '0';
            num_word <= (others => '0');
          end if;

        end if;

      end if;
    end if;
  end process;

end Behavioral;