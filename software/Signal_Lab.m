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
    end
    
    properties(SetAccess = protected)
        %
        % R/W registers
        %
        regs                %4 element registers
        adcreg
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
            self.regs = DeviceRegister.empty;
            for nn = 1:4
                self.regs(nn) = DeviceRegister((nn - 1)*4,self.conn);
            end
            self.adcreg = DeviceRegister('10',self.conn);
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

        end
        
        function self = setDefaults(self,varargin)
            self.leds.set(0);
            self.usedds(1).set(0);
            self.usedds(2).set(0);
            self.dac(1).set(0);
            self.dac(2).set(0);
            self.freq(1).set(1e6);
            self.freq(2).set(1e6);
            
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
        
        function self = upload(self)
            self.check;
            self.settings.write;
            self.regs.write;
        end
        
        function self = fetch(self)
            %Read registers
            self.regs.read;
            self.adcreg.read;
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
        end
        
        function self = resetdelay(self)
            self.regs(1).set(1,[10,10]).write;
            self.regs(1).set(0,[10,10]).write;
        end
        
        function self = getPhaseData(self,numSamples,saveFlags,startFlag,saveType)
            if nargin < 3
                saveFlags = '-p';
            end
            if nargin < 4 || startFlag == 0
                startFlag = '';
            else
                startFlag = '-b';
            end
            
            if nargin < 5
                saveType = 2;
            end
            
            self.conn.write(0,'mode','acquire phase','numSamples',numSamples,...
                'saveStreams',saveFlags,'saveType',0,'startFlag',startFlag,...
                'saveType',saveType);
            raw = typecast(self.conn.recvMessage,'uint8');
            d = self.convertData(raw,'phase',saveFlags);
            self.data = d;
            self.t = 1/self.CLK*2^self.cicRate.value*(0:(numSamples-1));
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
        end
        
        
    end
    
    methods(Static)
        function d = loadData(filename,dt,flags)
            if nargin == 0 || isempty(filename)
                filename = 'SavedData.bin';
            end
            
            %Load data
            fid = fopen(filename,'r');
            fseek(fid,0,'eof');
            fsize = ftell(fid);
            frewind(fid);
            x = fread(fid,fsize,'uint8');
            fclose(fid);
            
            d = PhaseLock.convertData(x,'phase',flags);
            if ~isempty(d.ph)
                N = numel(d.ph);
            elseif ~isempty(d.act)
                N = numel(d.act);
            elseif ~isempty(d.dds)
                N = numel(d.dds);
            end
            d.t = dt*(0:(N-1));
        end
        
        function varargout = convertData(raw,method,flags)
            if nargin < 3 || isempty(flags)
                streams = 1;
            else
                streams = 0;
                if contains(flags,'p')
                    streams = streams + 1;
                end
                
                if contains(flags,'s')
                    streams = streams + 2;
                end
                
                if contains(flags,'d')
                    streams = streams + 4;
                end
            end
            raw = raw(:);
            Nraw = numel(raw);
            bits = bitget(streams,1:7);
            numStreams = sum(bits);
            d = zeros(Nraw/(numStreams*4),numStreams,'uint32');
            
            raw = reshape(raw,4*numStreams,Nraw/(4*numStreams));
            for nn = 1:numStreams
                d(:,nn) = typecast(uint8(reshape(raw((nn-1)*4+(1:4),:),4*size(d,1),1)),'uint32');
            end
            
            switch lower(method)
                case 'voltage'
                    v = double(d)/2^12;
                    varargout{1} = v;
                case 'phase'
                    data.ph = [];
                    data.sum = [];
                    data.dds = [];
                    if bits(1)
                        data.ph = double(typecast(d(:,1),'int32'))/2^(PhaseLock.CORDIC_WIDTH-3)*pi;
                    end
                    if bits(2)
                        idx = sum(bits(1:2));
%                         data.act = unwrap(double(d(:,idx))/2^(PhaseLock.CORDIC_WIDTH-3)*pi);
                        data.sum = double(typecast(d(:,idx),'int32'))/2^(PhaseLock.CORDIC_WIDTH-3)*pi;
                    end
                    if bits(3)
                        idx = sum(bits(1:3));   
                        data.dds = unwrap(double(d(:,idx))/2^PhaseLock.DDS_WIDTH*2*pi);
                    end
                    varargout{1} = data;
                otherwise
                    error('Data type unsupported!');
            end
        end
    end
    
end