% BRIEF:
%   Controller function template. Input and output dimension MUST NOT be
%   modified.
% INPUT:
%   T: Measured system temperatures, dimension (3,1)
% OUTPUT:
%   p: Cooling power, dimension (2,1)
function p = controller_lqr(T)
% controller variables
persistent param;

% initialize controller, if not done already
if isempty(param)
    param = init();
end

% compute control action
%Lec7 Slide19
% u = u_sp -K(x-x_sp), so that u = u_sp when x = x_sp (kept in equilibrium)
 
 x = T - param.T_sp; %T_sp muss abgezogen werden
 u = -param.k * x;
 p = u + param.p_sp; %F�gen unseren Steady State point hinzu
end

function param = init()
param = compute_controller_base_parameters;
% add additional parameters if necessary, e.g.
[k_lqr, ~, ~] = dlqr(param.A, param.B, param.Q, param.R); %definitiv Minus K - kommt von der Dokumentation 
param.k = k_lqr;
end