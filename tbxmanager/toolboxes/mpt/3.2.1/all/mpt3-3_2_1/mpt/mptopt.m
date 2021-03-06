classdef mptopt < handle
    % Change MPT3 settings
    %
    % Settings can be modified by providing "Property", "Value" pairs:
	%
	%   mptopt('lpsolver', 'cdd', 'abs_tol', 1e-8)
    %
	% List of most important properties:
	%      lpsolver
	%      qpsolver
	%    milpsolver
	%     plpsolver
	%     pqpsolver
	%       rel_tol
	%       abs_tol
    %
	% Call "mptopt" to see the full list of supported properties.
    
    %% PROPERTIES
    % fixed properties
    properties (Constant)
        version = '@version@';
    end
    
    % internal properties
    properties (Constant, Hidden)
        OK         = 1; % Optimization results
        INFEASIBLE = 2;
        UNBOUNDED  = 3;
        ERROR      = -1; % Unknown return from the optimizer
        
%         OK_TXT         = 'Ok';
%         INFEASIBLE_TXT = 'Infeasible';
%         UNBOUNDED_TXT  = 'Unbounded'
%         ERR_TXT        = 'Error';
        
    end
    
    properties (SetAccess=private, SetObservable)
        solvers_list = mpt_subSolvers;
    end
    
    % adjustable properties
    properties (SetObservable, AbortSet)
        % default settings
              
        % assignment any of these values is checked in active set-methods
        rel_tol = 1e-6; % checking of active constraints
        abs_tol = 1e-8; % rank, general comparisons <,>, convergence, inversion
        lex_tol = 1e-10; % lexicographic tolerance 
        zero_tol = 1e-12;  % zero tolerance
        region_tol = 1e-7; % regions with diameter less than the one of inscribed ball (twice the Chebyshev radius) are considered as empty  
        report_period = 2; % Number of seconds between progress reports for long algorithms
        verbose = 0; % verbosity level [0,1,2]

        infbound = 1e4; 
		% colormap generated by hsv(10)
        colormap = [1 0 0; ...
			1 0.6 0; ...
			0.8 1 0; ...
			0.2 1 0; ...
			0 1 0.4; ...
			0 1 1; ...
			0 0.4 1; ...
			0.2 0 1; ...
			0.8 0 1; ...
			1 0 0.6];
        % not checked properties        
        %external_files = '';
        lpsolver = mpt_subSolvers('lp');
        qpsolver = mpt_subSolvers('qp');
        milpsolver = mpt_subSolvers('milp');
        miqpsolver = mpt_subSolvers('miqp');
        lcpsolver = mpt_subSolvers('lcp');
        plpsolver = mpt_subSolvers('plp');
        pqpsolver = mpt_subSolvers('pqp');
        plcpsolver = mpt_subSolvers('plcp');
        modules = mpt_subModules;
        % sdpsettings = mptopt.subSdpSettings;
        
        % additional properties are allowed, these are detected dynamically
        % by the constructor
        % if you want to add a property that requires checking of input
        % arguments, do that in set.methods
        
    end

    %% METHODS
    methods
        
        %% constructor
        function options = mptopt(varargin)
            
            % export global variable
            %
            % NOTE!
            %
            % accessing MPTOPTIONS from a global variable is much more
            % faster than calling mptopt!!! call mptopt only in case
            % MPTOPTIONS has been cleared from workspace
            %
            global MPTOPTIONS

            % if MPTOPTIONS already exist and are not empty, use them
            if ~isempty(MPTOPTIONS)
                options = MPTOPTIONS;
                if nargin>0
                    % list of available properties (allows adding of new
                    % properties)
                    p = properties('mptopt');
                    if  nargin==1 && isstruct(varargin{1}),
                        %special case - input is a structure
                        opt = varargin{1};
                        f = fieldnames(opt);
                        for ii=1:length(f),
                            if any(strcmp(f{ii},p))
                                % if the field name matches with a class property,
                                % assign the value
                                options.(f{ii}) = opt.(f{ii});
                            else
                                error('mptopt: There is no field with name "%s" in "mptopt" class.',f{ii});
                            end
                        end
                    end

                end
            else
                % an error might occur when loading/saving file in parallel mode
                try
                    p = properties('mptopt');
                    
                    if nargin==0 && ispref('MPT','MPTOPTIONS')
                        % if MPTOPTIONS have been saved as preferences, use those
                        % values
                        opt_struct=getpref('MPT','MPTOPTIONS');
                        %disp('MPT Options loaded.');
                        if ~isa(opt_struct,'struct')
                            disp('mptopt: Corrupted settings found, reinitializing...');
                            rmpref('MPT','MPTOPTIONS');
                            % start again
                            mptopt;
                        else
                            for i=1:numel(p)
                                % assign only dynamic properties
                                if ~any(strcmp(p{i},mptopt.constant_properties))
                                    options.(p{i}) = opt_struct.(p{i});
                                end
                            end
                        end
                    end
                    
                    % save preferences as structure whenever a change in settings is detected
                    nf = fieldnames(options);
                    for i=1:length(nf)
                        S.(nf{i}) = options.(nf{i});
                    end
                    %S = struct(options);
                    % remove listener because it causes troubles when running in
                    % parallel (it is added below anyway)
                    if isfield(S,'AutoListeners__')
                        S = rmfield(S,'AutoListeners__');
                    end
                    setpref('MPT','MPTOPTIONS',S);
                    
                    % delete static properties
                    sp = mptopt.constant_properties;
                    for i=1:numel(sp)
                        % delete static properties
                        p(strcmp(sp{i},p))=[];
                    end

                    % whenever an option value is changed, save it
                    addlistener(options,p,'PostSet',@(src,evnt)options.saveMPTpref(options,src,evnt));
                end
                % export global variable
                MPTOPTIONS = options;

            end
            %check if input arguments consist of pairs PropertyName, PropertyValue
            if nargin>=1 && ~isstruct(varargin{1}) 
                if rem(nargin, 2)~=0
                    error(['mptopt: Input arguments following the object name must be pairs', ...
                        ' of the form PropertyName, PropertyValue']);
                end
                %set the appropriate fields based on input arguments
                for ii=1:2:nargin
                    if ~ischar(varargin{ii})
                        error('mptopt: Property name is a string.');
                    end
                    set(options, varargin{ii}, varargin{ii+1});
                end
            end
            
        end

        function value = get(obj, prop)
            % returns the given property
            %
            %   get(mptopt, 'modules.solvers')
            
            narginchk(2, 2);
            value = obj;
            while ~isempty(prop)
                [token, prop] = strtok(prop, '.');
                value = value.(token);
            end
        end
        function set(obj, prop, value)
            % sets the given property to given value
            %
            %   set(mptopt, 'modules.ui.invariantSet.maxIterations', 1000)
            
            narginchk(3, 3);
            if isa(value, 'double')
                value = num2str(value);
            elseif ischar(value)
                value = ['''' value ''''];
            else
                error('The value must be a double or a string.');
            end
            accessor = 'obj';
            f = obj;
            up_till_now = '';
            while ~isempty(prop)
                [token, prop] = strtok(prop, '.');
                up_till_now = [up_till_now '.' token];
                if ~(isprop(f, token) || (isstruct(f) && isfield(f, token)))
                    error('No such property "%s".', up_till_now(2:end));
                end
                accessor = [accessor, '.(', '''', token, '''', ')'];
                f = f.(token);
            end
            accessor = [accessor '=' value ';'];
            eval(accessor);
        end
        
        %% SET methods
        %checking tolerance arguments
        function set.rel_tol(obj,val)
            global MPTOPTIONS
            
            % since we cannot refer to other property, we need to load the
            % stored data or refer to global variable MPTOPTIONS
            if isempty(MPTOPTIONS)
                st = getpref('MPT','MPTOPTIONS');
                abstol = st.abs_tol;
            else
                abstol = MPTOPTIONS.abs_tol;
            end
            
            % checking for relative tolerance
            if ~isnumeric(val)
                error('mptopt: Relative tolerance must be a numerical value.');
            elseif numel(val)~=1
                error('mptopt: Relative tolerance must be a scalar.');
            elseif val>1e-4 || val<1e-6 || val<abstol
                error('mptopt: Relative tolerance is not allowed to be bigger than 1e-4 and less than 1e-6 or "abs_tol".');
            else
                obj.rel_tol = val;
            end
        end
        function set.abs_tol(obj,val)
            global MPTOPTIONS

            % since we cannot refer to other property, we need to load the
            % stored data or refer to global variable MPTOPTIONS            
            if isempty(MPTOPTIONS)
                st = getpref('MPT','MPTOPTIONS');
                reltol = st.rel_tol;
                lextol = st.lex_tol;
            else
                reltol = MPTOPTIONS.rel_tol;
                lextol = MPTOPTIONS.lex_tol;
            end
            
            % checking for absolute tolerance
            if ~isnumeric(val)
                error('mptopt: Absolute tolerance must be a numerical value.');
            elseif numel(val)~=1
                error('mptopt: Absolute tolerance must be a scalar.');
            elseif val>1e-4 || val>reltol || val<lextol
                error('mptopt: Absolute tolerance is not allowed to be bigger than 1e-4 and it must be in the interval "rel_tol" < "abs_tol" < "lex_tol".')
            else
                obj.abs_tol = val;
            end
        end        
        function set.lex_tol(obj,val)
            global MPTOPTIONS
            
            % since we cannot refer to other property, we need to load the
            % stored data or refer to global variable MPTOPTIONS           
            if isempty(MPTOPTIONS)
                st = getpref('MPT','MPTOPTIONS');
                abstol = st.abs_tol;
                zerotol = st.zero_tol;
            else
                abstol = MPTOPTIONS.abs_tol;
                zerotol = MPTOPTIONS.zero_tol;
            end
                
            
            % checking for lexicographic tolerance
            if ~isnumeric(val)
                error('mptopt: Lexicographic tolerance must be a numerical value.');
            elseif numel(val)~=1
                error('mptopt: Lexicographic tolerance must be a scalar.');
            elseif val>1e-7 || val>abstol || val<zerotol
                error('mptopt: Lexicographic tolerance is not allowed to be bigger than 1e-7 and it must be in the interval "abs_tol" < "lex_tol" < "zero_tol".')                
            else
                obj.lex_tol= val;
            end
        end
        function set.zero_tol(obj,val)
            global MPTOPTIONS

            % since we cannot refer to other property, we need to load the
            % stored data or refer to global variable MPTOPTIONS           
            if isempty(MPTOPTIONS)
                st = getpref('MPT','MPTOPTIONS');
                lextol = st.lex_tol;
            else
                lextol = MPTOPTIONS.lex_tol;
            end

            % checking for zero tolerance
            if ~isnumeric(val)
                error('mptopt: Zero tolerance must be a numerical value.');
            elseif numel(val)~=1
                error('mptopt: Zero tolerance size must be a scalar.');
            elseif val>1e-10 || val>lextol || val<1e-15
                error('mptopt: Zero tolerance is not allowed to be bigger than 1e-10 and less than 1e-15 or "lex_tol".')
            else
                obj.zero_tol = val;
            end
        end
        function set.region_tol(obj,val)            
            % checking for region tolerance
            if ~isnumeric(val)
                error('mptopt: Tolerance must be a numerical value.');
            elseif numel(val)~=1
                error('mptopt: Tolerance size must be a scalar.');
            elseif val<1e-8 || val>1e-4
                error('mptopt: Region tolerance is not allowed to be bigger than 1e-4 and less than 1e-8.')                
            else
                obj.region_tol = val;
            end
        end        
        function set.verbose(obj,val)
            % checking for a verbose level
            if ~ismember(val,[0 1 2])
                error('mptopt: Verbose level can be only 0, 1, or 2.');
            elseif ~isnumeric(val)
                error('mptopt: Verbose level must be a numerical value.');
            elseif numel(val)~=1
                error('mptopt: Verbose level size must be a scalar.');
            else
                obj.verbose = val;
            end
        end
%         function set.rescue(obj,val)
%             % rescue option
%             if ~ismember(val,[0 1])
%                 error('mptopt: Rescue option can be only 0, or 1.');
%             elseif ~isnumeric(val)
%                 error('mptopt: Rescue option must be a numerical value.');
%             elseif numel(val)~=1
%                 error('mptopt: Rescue level size must be a scalar.');
%             else
%                 obj.rescue = val;
%             end
%         end
        function set.report_period(obj,val)
            % checking report period
            if ~isnumeric(val)
                error('mptopt: Report period must be a numerical value.');
            elseif numel(val)~=1
                error('mptopt: Report period must be a scalar.');
            elseif val<0
                error('mptopt: Report period must be positive.')
            else
                obj.report_period = val;
            end
        end
        function set.infbound(obj,val)
            % checking infbound
            if ~isnumeric(val)
                error('mptopt: Value for "infbound" must be a numeric.');
            elseif numel(val)~=1
                error('mptopt: Value for "infbound" must be a scalar.');
            elseif val<0
                error('mptopt: Value for "infbound" must be positive.')                
            else
                obj.infbound = val;
            end
        end
        function set.colormap(obj,val)
            % checking colormap
            if size(val,2)~=3
                error(['mptopt: Colormap can have any number of rows but must have exactly three columns.',...
                    'Each row is interpreted as a color, with the first element specifying the',...
                    'intensity of red light, the second green, and the third blue. Color intensity',...
                    'can be specified on the interval 0.0 to 1.0.']);
            elseif max(max(val))>1 || min(min(val))<0
                error('mptopt: Colormap values must be within interval [0, 1].');
            elseif ~isnumeric(val)
                error('mptopt: Colormap must be a numerical value.');
            else
                obj.colormap = val;
            end
        end
%         function set.solvers_list(obj,val)
%                                  
% %             % prepare strings of solvers
% %             s = {'LP','QP','MILP','MIQP','LCP','parametric'};
% %             
% %             % test if the input argument fulfills all criteria for
% %             % assigning solvers values (to avoid recursive calling of this
% %             % SET-method)
% %             if isa(val,'struct')
% %                 test_struct = zeros(1,2*length(s));
% %                  for i=1:length(s)
% %                      fn = s{i};
% %                      if isfield(val,fn) 
% %                           test_struct(i) = true;
% %                           if iscell(val.(fn))
% %                               test_struct(i+length(s)) = true;
% %                           end
% %                      end                     
% %                  end
% %                  if all(test_struct)
% %                     obj.solvers_list = val;
% %                     return
% %                  end
% %             end
%             if ~isa(val,'struct')
%                 % when trying to overwrite default values, run
%                 % mpt_detect_solvers and print a notice
%                 disp(' ');
%                 
%                 Rs = input('Do you wish to search for solvers on the path? Y/N [N]: ','s');
%                 if strcmpi(Rs,'y')
%                     L = mpt_detect_solvers;
%                 else
%                     L = obj.solvers_list;
%                 end
%                 
%                 disp(' ');
%                 disp('This is list of found solvers that work.');
%                 disp('You are only allowed to change the order these solvers.');
%                 disp('Order can be changed by assigning a different preference value.');
%                 disp(' ');
%                 
%                 % extract fields of the solvers list
%                 s = fieldnames(L);
%                 
%                 for i=1:length(s);
%                     while 1
%                         disp([' ',s{i},' solver : preference value ']);
%                         disp('-------------------------------');
%                         s_list = L.(s{i});
%                         p_list = zeros(length(s_list),1);
%                         for j=1:length(s_list)
%                             p_list(j) = 10*j;
%                             fprintf('%s%s: %d \n',repmat(' ', 1, 14-length(s_list{j})),s_list{j},p_list(j));
%                         end
%                         disp('-------------------------------');
%                         disp(' ');
%                         R = input(['Do you want to change the order of ',s{i},' solvers? Y/N [N]: '], 's');
%                         if isempty(R) || strcmpi(R,'n')
%                             R = 'N';
%                         elseif strcmpi(R,'Y')
%                             R = 'Y';
%                         else
%                             fprintf('Wrong input, assuming N.\n');
%                         end
%                         if strcmp(R,'Y')
%                             while 1
%                                 sn = input('Type name of the solver you want to change from the list above: ','s');
%                                 inds = strmatch(sn,s_list,'exact');
%                                 if ~isempty(inds)
%                                     break
%                                 else
%                                     disp('Solver not in the list, try again.');
%                                 end
%                             end
%                             fprintf('The current preference value for this solver is %d.\n', p_list(inds));
%                             while 1
%                                 v = str2num(input('Type its new value: ','s'));
%                                 if isempty(v) || v<0
%                                     disp('Preference value must be of type double and nonnegative.');
%                                 else
%                                     % overwrite default order
%                                     p_list(inds) = v;
%                                     % get indices of the ordered list
%                                     [~, ind_p] = sort(p_list);
%                                     % sort according to indices
%                                     L.(s{i}) = s_list(ind_p);
%                                     obj.solvers_list = L;
%                                     %keyboard
%                                     fprintf('\n');
%                                     break
%                                 end
%                             end
%                         else
%                             % save list
%                             obj.solvers_list = L;
%                             fprintf('\n');
%                             break
%                         end
%                         
%                     end
%                 end
%             end
%         end
        
        function set.lpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.LP))
                error('mptopt: Given solver is not in the list of LP solvers.');
            end
            obj.lpsolver = v;
        end
        function set.qpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.QP))
                error('mptopt: Given solver is not in the list of QP solvers.');
            end
            obj.qpsolver = v;
        end
        
        function set.milpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.MILP))
                error('mptopt: Given solver is not in the list of MILP solvers.');
            end
            obj.milpsolver = v;
        end
        
        function set.miqpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.MIQP))
                error('mptopt: Given solver is not in the list of MIQP solvers.');
            end
            obj.miqpsolver = v;
        end
        
        function set.lcpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.LCP))
                error('mptopt: Given solver is not in the list of LCP solvers.');
            end
            obj.lcpsolver = v;
        end
        
        function set.plpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.parametric.LP))
                error('mptopt: Given solver is not in the list of linear parametric solvers.');
            end
            obj.plpsolver = v;
        end
        
        function set.pqpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.parametric.QP))
                error('mptopt: Given solver is not in the list of quadratic parametric solvers.');
            end
            obj.pqpsolver = v;
        end
        
        function set.plcpsolver(obj,val)
            % checks if the solver is ok to be set as default            
            if ~ischar(val)
                error('mptopt: The solver must be given as a string.');
            end

            % get the list of solvers
            s = mpt_subSolvers;
            
            % get rid of spaces and make capital
            v = upper(strtrim(val));
            if ~any(strcmp(v,s.parametric.LCP))
                error('mptopt: Given solver is not in the list of linear-complementarity parametric solvers.');
            end
            obj.plcpsolver = v;
        end
        
%         function set.modules(obj,val)
%             % settings for modules are not checked (local options)
%             global MPTOPTIONS
%                         
%             % update global variable (without additional checks)
%             MPTOPTIONS.modules = val;
%         end
        
        %% Default display
        function disp(obj)
            p = properties('mptopt');
        
            fprintf(' Global settings for MPT:\n');
            for i=1:length(p)
                s = obj.(p{i});
                if ischar(s)
                    fprintf('%s%s: %s',repmat(' ',1,25-length(p{i})),p{i},s);
                elseif isnumeric(s)
                    if numel(s)<=1
                        fprintf('%s%s: %g',repmat(' ',1,25-length(p{i})),p{i},s);
                    else
                        fprintf('%s%s: matrix of size [%d x %d]',repmat(' ',1,25-length(p{i})),p{i},size(s,1),size(s,2));
                    end
                else
                    fprintf('%s%s: [%s]',repmat(' ',1,25-length(p{i})),p{i},class(s));
                end
%                 m = findprop(mptopt,p{i});
%                 if m.Constant
%                     fprintf(' (constant) \n');
%                 else
                     fprintf(' \n');
%                 end
            end
            
%              fprintf('\n To change the setting, you can use one of the following syntax:\n');
%              fprintf(' MPTOPT(''PropertyName'',PropertyValue)\n\n');

        end
        
    end
            
    methods (Static)
        function col = getRandColor
            %
            % Return a random color from the MPT colormap
            %
            narginchk(0, 0);
            a = mptopt;
            i = ceil(rand*size(a.colormap,1));
            col = a.colormap;
            col = col(i,:);
        end
        
%         function str = errToTxt(err)
%             % ERRTOTXT Convert an MPT error to a text string
%             %
%             % errToTxt(err)
%             %
%             
%             switch err
%                 case mptopt.OK,         str = mptopt.OK_TXT;
%                 case mptopt.INFEASIBLE, str = mptopt.INFEASIBLE_TXT;
%                 case mptopt.UNBOUNDED,  str = mptopt.UNBOUNDED_TXT;
%                 case mptopt.ERR,        str = mptopt.ERR_TXT;
%                 otherwise
%                     str = 'Unknown error type';
%             end
%             
%         end
              
%
% DUE TO RECURSIVE CALLING OF MPTOPT CLASS IS THIS METHOD DISABLED
%
%         function prop = getProp(key)
%             %
%             % Returns required property form "mptopt" class
%             % e.g. mptopt.getProp('abs_tol')
%             %      mptopt.getProp({'abs_tol','rel_tol'})
%             %
%             if nargin~=1
%                 error('mptopt:getProp: One argument is required.');
%             end
%             if not( ischar(key) || iscell(key))
%                 error('mptopt:getProp: Input argument must be a string, or a cell of strings.');
%             end
%             % get mptopt object
%             a = mptopt;
%             % get all properties
%             p = properties(a);
%             % assign properties
%             if ischar(key)
%                 key = {key};
%             end
%             % prepare output
%             prop = cell(size(key));
%             for i=1:length(key)
%                 if strmatch(key{i},p,'exact');
%                     prop{i} = a.(key{i});
%                 else
%                     error('mptopt:getProp: There is no property "%s" in "mptopt" class.',key{i});
%                 end
%             end
%             % for one property do not return a cell
%             if numel(prop)==1
%                 prop = prop{1};
%             end
%         end
        
        function y = properties
            % returns a list of properties for "mptopt" class
            narginchk(0, 0);
            y = properties('mptopt');
        end
        
        function y = constant_properties
            % returns a list of constant properties for "mptopt" class
            narginchk(0, 0);
            m = ?mptopt;
            y = [];
            for i=1:length(m)
                if m.Properties{i}.Constant
                    y = [y; {m.Properties{i}.Name}];
                end
            end
        end
    end
    
    methods (Static, Hidden)
        %% LISTENERS
        function saveMPTpref(options,src,evnt)
            % this function must have at least 2 arguments         

            % save preferences as structure whenever a change in settings is detected
            nf = fieldnames(options);
            for i=1:length(nf)
                S.(nf{i}) = options.(nf{i});
            end

            % remove listener because it causes troubles when running in
            % parallel
            if isfield(S,'AutoListeners__')
                S = rmfield(S,'AutoListeners__');
            end
            setpref('MPT','MPTOPTIONS',S);

            % inform user
            %disp('New settings for MPT toolbox have been saved.');                        
        end
    
    end

end
