classdef Signal_Lab < handle
    properties
        t
        data
    end
    
    properties(SetAccess = immutable)
        conn        %ConnectionClient object for communicating with device
        %
        % IO Setttings
        %
        settings
        %
        % Top-level properties
        %
        leds        %LED outputs
        dac         %2-channel DAC outputs
        freq        %2-element frequency settings for DDSs
        usedds      %Set to 0 to use DDS, 1 to use manual DAC
        adc         %2-channel ADC inputs
        numSamples  %Number of samples to acquire
        lastSample  %Last sample
    end
    
    properties(SetAccess = protected)
        %
        % R/W registers
        %
        triggers
        regs                %4 element registers
        adcreg
        numSamplesReg
        memreg
    end
    
    properties(Constant)
        CLK = 250e6;                    %Clock frequency of the board
        HOST_ADDRESS = '';              %Default socket server address
        DAC_WIDTH = 14;                 %DAC width
        ADC_WIDTH = 12;                 %ADC width
    end
    
    methods
        function self = Signal_Lab(varargin)
            if numel(varargin) == 1
                self.conn = ConnectionClient(varargin{1});
            else
                self.conn = ConnectionClient(self.HOST_ADDRESS);
            end
            
            self.settings = IOSettings(self);
            
            % R/W registers
            self.triggers = DeviceRegister(0,self.conn);
            self.regs = DeviceRegister.empty;
            for nn = 1:4
                self.regs(nn) = DeviceRegister((nn - 0)*4,self.conn);
            end
            self.adcreg = DeviceRegister('14',self.conn);
            self.numSamplesReg = DeviceRegister('18',self.conn);
            self.memreg = DeviceRegister('1C',self.conn);
            %
            % Parameters
            %
            self.leds = DeviceParameter([0,7],self.regs(1))...
                .setLimits('lower',0,'upper',255)...
                .setFunctions('to',@(x) x,'from',@(x) x);
            self.usedds = DeviceParameter([8,8],self.regs(1))...
                .setLimits('lower',0,'from',1);
            self.usedds(2) = DeviceParameter([9,9],self.regs(1))...
                .setLimits('lower',0,'from',1);
            self.dac = DeviceParameter([0,15],self.regs(2),'int16')...
                .setLimits('lower',-10,'upper',10)...
                .setFunctions('to',@(x) self.convertDAC(x,'int',1),'from',@(x) self.convertDAC(x,'volt',1));
            self.dac(2) = DeviceParameter([16,31],self.regs(2),'int16')...
                .setLimits('lower',-10,'upper',10)...
                .setFunctions('to',@(x) self.convertDAC(x,'int',2),'from',@(x) self.convertDAC(x,'volt',2));
            self.freq = DeviceParameter([0,31],self.regs(3))...
                .setLimits('lower',0,'upper',60e6)...
                .setFunctions('to',@(x) x/self.CLK*2^32,'from',@(x) x/2^32*self.CLK);
            self.freq(2) = DeviceParameter([0,31],self.regs(4))...
                .setLimits('lower',0,'upper',60e6)...
                .setFunctions('to',@(x) x/self.CLK*2^32,'from',@(x) x/2^32*self.CLK);
            
            self.adc = DeviceParameter([0,15],self.adcreg,'int16')...
                .setFunctions('from',@(x) self.convertADC(x,'volt',1));
            self.adc(2) = DeviceParameter([16,31],self.adcreg,'int16')...
                .setFunctions('from',@(x) self.convertADC(x,'volt',1));

            self.numSamples = DeviceParameter([0,13],self.numSamplesReg)...
                .setLimits('lower',0,'upper',2^14 - 1);
            self.lastSample = DeviceParameter([0,31],self.memreg);
        end
        
        function self = setDefaults(self,varargin)
            self.leds.set(0);
            self.usedds(1).set(0);
            self.usedds(2).set(0);
            self.dac(1).set(0);
            self.dac(2).set(0);
            self.freq(1).set(1e6);
            self.freq(2).set(1e6);
            
            self.numSamples.set(1e4);
            self.settings.setDefaults;
        end
        
        function self = check(self)

        end
        
        function r = convertDAC(self,v,direction,ch)
            g = (self.settings.convert_gain(ch) == 0)*1 + (self.settings.convert_gain(ch) == 1)*5;
            if strcmpi(direction,'int')
                r = v/(g*2)*(2^(self.DAC_WIDTH - 1) - 1);
            elseif strcmpi(direction,'volt')
                r = (g*2)*v/(2^(self.DAC_WIDTH - 1) - 1);
            end
        end
        
        function r = convertADC(self,v,direction,ch)
            g = (self.settings.convert_attenuation(ch) == 0)*1.1 + (self.settings.convert_attenuation(ch) == 1)*20;
            if strcmpi(direction,'int')
                r = v/(g)*(2^(self.ADC_WIDTH + 1) - 1);
            elseif strcmpi(direction,'volt')
                r = (g)*v/(2^(self.ADC_WIDTH  + 1) - 1);
            end
        end
        
        function self = start(self)
            self.triggers.set(1,[0,0]);
            self.triggers.write;
            self.triggers.set(0,[0,0]);
        end
        
        function self = upload(self)
            self.check;
            self.settings.write;
            self.regs.write;
            self.numSamplesReg.write;
        end
        
        function self = fetch(self)
            %Read registers
            self.regs.read;
            self.adcreg.read;
            self.numSamplesReg.read;
            self.memreg.read;
            %Read parameters
            self.leds.get;
            self.usedds(1).get;
            self.usedds(2).get;
            self.dac(1).get;
            self.dac(2).get;
            self.freq(1).get;
            self.freq(2).get;
            self.adc(1).get;
            self.adc(2).get;
            
            self.numSamples.get;
            self.lastSample.get;
        end
        
        function self = resetdelay(self)
            self.regs(1).set(1,[10,10]).write;
            self.regs(1).set(0,[10,10]).write;
        end
        
        function self = getRAM(self,numSamples)
            if nargin < 2
                self.conn.keepAlive = true;
                self.lastSample.read;
                self.conn.keepAlive = false;
                numSamples = self.lastSample.value;
            end
            self.conn.write(0,'mode','fetch ram','numSamples',numSamples);
            raw = typecast(self.conn.recvMessage,'uint8');
            
            d = self.convertData(raw);
            self.data = zeros(size(d));
            for nn = 1:size(self.data,2)
                self.data(:,nn) = self.convertADC(d(:,nn),'volt',nn);
            end
            dt = self.CLK^-1;
            self.t = dt*(0:(size(self.data,1)-1));
        end
        
        function disp(self)
            strwidth = 20;
            fprintf(1,'Signal_Lab object with properties:\n');
            self.settings.print(strwidth);
            fprintf(1,'% 5s~~~~~~~~~~~~~~~~~~~~~~~~~\n',' ');
            fprintf(1,'\t Registers\n');
            for nn = 1:numel(self.regs)
                self.regs(nn).print(sprintf('Register %d',nn),strwidth);
            end
            self.numSamplesReg.print('Num. Samples. Reg',strwidth);
            self.memreg.print('Memory register',strwidth);
            self.adcreg.print('ADC Register',strwidth);
            self.leds.print('LEDs',strwidth,'%08x');
            self.usedds(1).print('Use DDS 1',strwidth,'%d');
            self.usedds(2).print('Use DDS 2',strwidth,'%d');
            self.dac(1).print('DAC 1',strwidth,'%.3f','V');
            self.dac(2).print('DAC 2',strwidth,'%.3f','V');          
            self.freq(1).print('Frequency 1',strwidth,'%.3e','MHz');
            self.freq(2).print('Frequency 2',strwidth,'%.3e','MHz');
            self.adc(1).print('ADC 1',strwidth,'%.3f','V');
            self.adc(2).print('ADC 2',strwidth,'%.3f','V');   
            self.numSamples.print('Number of samples',strwidth,'%d');
            self.lastSample.print('Samples collected',strwidth,'%d');
        end
    end
    
    methods(Static)
        function v = convertData(raw,c)
            %CONVERTDATA Converts raw data into proper int16/double format
            %
            %   V = CONVERTDATA(RAW) Unpacks raw data from uint8 values to
            %   a pair of double values for each measurement
            %
            %   V = CONVERTDATA(RAW,C) uses conversion factor C in the
            %   conversion
            
            if nargin < 2
                c = 1;
            end
            
            Nraw = numel(raw);
            d = zeros(Nraw/4,2,'int16');
            
            mm = 1;
            for nn = 1:4:Nraw
                d(mm,1) = typecast(uint8(raw(nn + (0:1))),'int16');
                d(mm,2) = typecast(uint8(raw(nn + (2:3))),'int16');
                mm = mm + 1;
            end
            
            v = double(d)*c;
        end
    end
end