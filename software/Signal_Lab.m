classdef Signal_Lab < handle
    properties
        t
        data
        
        outputGains
        inputGains
    end
    
    properties(SetAccess = immutable)
        conn        %ConnectionClient object for communicating with device
        %
        % Top-level properties
        %
        leds        %LED outputs
        dac         %2-channel DAC outputs
        
    end
    
    properties(SetAccess = protected)
        %
        % R/W registers
        %
        regs                %4 element registers

    end
    
    properties(Constant)
        CLK = 250e6;                    %Clock frequency of the board
        HOST_ADDRESS = '';              %Default socket server address
        DAC_WIDTH = 14;                 %DAC width
    end
    
    methods
        function self = Signal_Lab(varargin)
            if numel(varargin)==1
                self.conn = ConnectionClient(varargin{1});
            else
                self.conn = ConnectionClient(self.HOST_ADDRESS);
            end
            
            % R/W registers
            self.regs = DeviceRegister.empty;
            for nn = 1:4
                self.regs(nn) = DeviceRegister((nn - 1)*4,self.conn);
            end
            %
            % Parameters
            %
            self.leds = DeviceParameter([0,7],self.regs(1))...
                .setLimits('lower',0,'upper',255)...
                .setFunctions('to',@(x) x,'from',@(x) x);
            self.dac = DeviceParameter([0,15],self.regs(2),'int16')...
                .setLimits('lower',-10,'upper',10)...
                .setFunctions('to',@(x) self.convertDAC(x,'int',1),'from',@(x) self.convertDAC(x,'volt',1));
            self.dac(2) = DeviceParameter([16,31],self.regs(2),'int16')...
                .setLimits('lower',-10,'upper',10)...
                .setFunctions('to',@(x) self.convertDAC(x,'int',2),'from',@(x) self.convertDAC(x,'volt',2));
            
            self.outputGains = [1,1];
            self.inputGains = [1,1];
        end
        
        function self = setDefaults(self,varargin)
            self.leds.set(0);
            self.dac(1).set(0);
            self.dac(2).set(0);
            
            self.outputGains = [1,1];
            self.inputGains = [1,1];
        end
        
        function self = check(self)

        end
        
        function r = convertDAC(self,v,direction,ch)
            if strcmpi(direction,'int')
                r = v/(self.outputGains(ch)*2)*(2^(self.DAC_WIDTH - 1) - 1);
            elseif strcmpi(direction,'volt')
                r = (self.outputGains(ch)*2)*v/(2^(self.DAC_WIDTH - 1) - 1);
            end
        end
        
        function self = setGains(self,gains)
            if nargin >= 2
                self.outputGains = gains;
            end
            
            g = (self.outputGains == 1)*0 + (self.outputGains == 5)*1;
            for nn = 1:numel(self.outputGains)
                self.conn.write(0,'mode','set output gain','port',nn,'value',g(nn));
            end
            
            for nn = 1:numel(self.inputGains)
                self.conn.write(0,'mode','set input gain','port',nn,'value',self.inputGains(nn));
            end
        end
        
        function self = upload(self)
            self.check;
            self.setGains;
            self.regs.write;
        end
        
        function self = fetch(self)
            %Read registers
            self.regs.read;
            
            %Read parameters
            self.leds.get;
            self.dac(1).get;
            self.dac(2).get;
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
            fprintf(1,'% 5sOutput gains: [%d,%d]\n',' ',self.outputGains);
            fprintf(1,'% 5s Input gains: [%d,%d]\n',' ',self.inputGains);
            fprintf(1,'% 5s~~~~~~~~~~~~~~~~~~~~~~~~~\n',' ');
            fprintf(1,'\t Registers\n');
            for nn = 1:numel(self.regs)
                self.regs(nn).print(sprintf('Register %d',nn),strwidth);
            end
            self.leds.print('LEDs',strwidth,'%08x');
            self.dac(1).print('DAC 1',strwidth,'%.3f','V');
            self.dac(2).print('DAC 1',strwidth,'%.3f','V');          
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