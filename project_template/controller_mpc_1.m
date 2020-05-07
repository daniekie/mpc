% yalmip('clear')
% clear all
% 
% % Model data
% A = [2 -1;1 0.2];
% B = sdpvar(2,1);
% E = [1;1];
% nx = 2; % Number of states
% nu = 1; % Number of inputs
% 
% % MPC data
% Q = eye(2);
% R = 2;
% N = 20;
% 
% 
% ny = 1;
% C = [1 0];
% 
% u = sdpvar(repmat(nu,1,N),repmat(1,1,N));
% x = sdpvar(repmat(nx,1,N+1),repmat(1,1,N+1));
% r = sdpvar(repmat(ny,1,N+1),repmat(1,1,N+1));
% d = sdpvar(1);
% pastu = sdpvar(1);
% 
% constraints = [-.1 <= diff([pastu u{:}]) <= .1];
% objective = 0;
% for k = 1:N
%     objective = objective + (C*x{k}-r{k})'*(C*x{k}-r{k}) + u{k}'*u{k};
%     constraints = [constraints, x{k+1} == A*x{k}+B*u{k}+E*d];
%     constraints = [constraints, -1 <= u{k}<= 1, -5<=x{k+1}<=5];
% end
% objective = objective + (C*x{N+1}-r{N+1})'*(C*x{N+1}-r{N+1});
% 
% parameters_in = {x{1},[r{:}],d,pastu,B};
% solutions_out = {[u{:}], [x{:}]};
% 
% controller = optimizer(constraints, objective,sdpsettings('solver','gurobi'),parameters_in,solutions_out);
% x = [0;0];
% clf;
% disturbance = randn(1)*.01;
% oldu = 0;
% hold on
% xhist = x;
% for i = 1:300
%     if i < 50
%         Bmodel = [1;0];
%     else
%         Bmodel = [.9;.1];
%     end
%     future_r = 3*sin((i:i+N)/40);    
%     inputs = {x,future_r,disturbance,oldu,Bmodel};
%     [solutions,diagnostics] = controller{inputs};    
%     U = solutions{1};oldu = U(1);
%     X = solutions{2};
%     if diagnostics == 1
%         error('The problem is infeasible');
%     end    
%     subplot(1,2,1);stairs(i:i+length(U)-1,U,'r')
%     subplot(1,2,2);cla;stairs(i:i+N,X(1,:),'b');hold on;stairs(i:i+N,future_r(1,:),'k')
%     stairs(1:i,xhist(1,:),'g')    
%     x = A*x + Bmodel*U(1)+E*disturbance;
%     xhist = [xhist x];
%     pause(0.05)   
%     % The measured disturbance actually isn't constant, it changes slowly
%     disturbance = 0.99*disturbance + 0.01*randn(1);
% end

% BRIEF:
%   Controller function template. This function can be freely modified but
%   input and output dimension MUST NOT be changed.
% INPUT:
%   T: Measured system temperatures, dimension (3,1)
% OUTPUT:
%   p: Cooling power, dimension (2,1)
function p = controller_mpc_1(T)
% controller variables
persistent param yalmip_optimizer

% initialize controller, if not done already
if isempty(param)
    [param, yalmip_optimizer] = init();
end

%% evaluate control action by solving MPC problem, e.g.
Tin = T - param.T_sp;
[u_mpc,errorcode] = yalmip_optimizer(Tin);
if (errorcode ~= 0)
      warning('MPC infeasible');
end
p = u_mpc{1} - param.p_sp;
end

function [param, yalmip_optimizer] = init()
% initializes the controller on first call and returns parameters and
% Yalmip optimizer object

param = compute_controller_base_parameters; % get basic controller parameters

%% implement your MPC using Yalmip here, e.g.
%MPC data
N = 30;
Q = param.Q;
R = param.R;

%Model data
A = param.A;
B = param.B;

nx = size(param.A,1);
nu = size(param.B,2);

u = sdpvar(repmat(nu,1,N-1), repmat(1,1,N-1), 'full');
x = sdpvar(repmat(nx,1,N), repmat(1,1,N), 'full');

objective = 0;
Gu = [1 0; -1 0; 1 0; -1 0];
Gx = [1 0 0; 0 1 0; 0 -1 0];
constraints = [];

for k = 1:N-1
  constraints = [constraints, Gu*u{k} <= param.Ucons];
  constraints = [constraints, Gx*x{k} <= param.Xcons];
  constraints = [constraints, x{k+1} == A*x{k}+B*u{k}];
  objective = objective + x{k}'*Q*x{k} + u{k}'*R*u{k};
end

% Timestep N
objective = objective + x{N}'*Q*x{N};
constraints = [constraints, Gx*x{N} <= param.Xcons];

ops = sdpsettings('verbose', 0, 'solver', 'quadprog');
fprintf('JMPC_dummy = %f', value(objective));
yalmip_optimizer = optimizer(constraints, objective, ops, x{1,1}, {u{1,1}, objective});
end