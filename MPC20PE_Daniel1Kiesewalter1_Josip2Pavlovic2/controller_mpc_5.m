% BRIEF:
%   Controller function template. This function can be freely modified but
%   input and output dimension MUST NOT be changed.
% INPUT:
%   T: Measured system temperatures, dimension (3,1)
% OUTPUT:
%   p: Cooling power, dimension (2,1)
function p = controller_mpc_5(T)
% controller variables
persistent param yalmip_optimizer d_hat x_hat



% initialize controller, if not done already
if isempty(param)
    % The disturbance has to be initialised as well
    [param, yalmip_optimizer] = init();
    % initialise the current state estimate to be the measured state
    d_hat = param.d;
    x_hat = T;    
end

% Get the steady state, using the equations from the lecture
steady_state = [param.A-eye(3),param.B; param.C_ref,zeros(2,2)]\[-param.B_d*d_hat;param.b_ref];
xs = steady_state(1:3);
us = steady_state(4:5);

% Define the input to the optimizer (current state and disturbance
% estimates)
x_aug = [x_hat;d_hat];
%% evaluate control action by solving MPC problem, e.g.
[u_mpc,errorcode] = yalmip_optimizer(x_aug,xs,us);
if (errorcode ~= 0)
      warning('MPC infeasible');
end
%Not in x_delta anymore
p = u_mpc{1};

% Update the estimated state and input
estimates = param.A_aug*x_aug + param.B_aug*p + param.L*(T-param.C_aug*x_aug);
% +C*x_hat
x_hat = estimates(1:3);
d_hat = estimates(4:6);

end
% Get the updated state and disturbance estimates


function [param, yalmip_optimizer] = init()
% initializes the controller on first call and returns parameters and
% Yalmip optimizer object

param = compute_controller_base_parameters; % get basic controller parameters

%% implement your MPC using Yalmip here, e.g.

N = 30;
nx = size(param.A_aug,1);
nu = size(param.B_aug,2);
[Axn,bxn]=compute_X_LQR;

U = sdpvar(repmat(nu,1,N-1),ones(1,N-1),'full');
X = sdpvar(repmat(nx,1,N),ones(1,N),'full');

xs = sdpvar(nx/2,1,'full');
us = sdpvar(nu,1,'full');

objective = (X{:,1}(1:3,:)-xs)'*param.Q*(X{:,1}(1:3,:)-xs)+(U{:,1}-us)'*param.R*(U{:,1}-us);
constraints = [param.Pcons(:,1)<=U{:,1}<=param.Pcons(:,2)];
for k = 2:N-1
  % State dynamic constraint, 
  constraints = [constraints, X{:,k}==param.A_aug*X{:,k-1}+param.B_aug*U{:,k-1}];
  % State constraints & input constraints
  constraints = [constraints,param.Pcons(:,1)<=U{:,k}<=param.Pcons(:,2),param.Tcons(:,1)<=X{:,k}(1:3)<=param.Tcons(:,2)]; 
  objective = objective + (X{:,k}(1:3,:)-xs)'*param.Q*(X{:,k}(1:3,:)-xs)+(U{:,k}-us)'*param.R*(U{:,k}-us);

end
constraints = [constraints, X{:,N}==param.A_aug*X{:,N-1}+param.B_aug*U{:,N-1}];
constraints = [constraints, Axn*(X{:,N}(1:3,:)-xs)<=bxn];
objective = objective + (X{:,N}(1:3,:)-xs)'*param.P*(X{:,N}(1:3,:)-xs) ;

ops = sdpsettings('verbose',0,'solver','quadprog');
yalmip_optimizer = optimizer(constraints,objective,ops,{X{1,1};xs;us},{U{1,1},objective});
end