% Init
clear all
close all
addpath(genpath(cd));
load('system/parameters_scenarios.mat');

%% E.g. execute simulation with LQR
% clear persisten variables of function controller_lqr
clear controller_lqr; 

T0_1 = [3; 1; 0] + [-21; 0.3; 7.32];
T0_2 = [-1; -0.3; -4.5] + [-21; 0.3; 7.32];
T0_3 = [12; 12; 12];

% %T5
% % % execute simulation starting from T0_1 using lqr controller with scenario 1
% [T, p] = simulate_truck(T0_1, @controller_lqr, scen1);
% % % Controller works with constraints. Norm constraint from question checked
% % % t_30 = [-20.64; 0.5786; 7.475]
% % % norm(T_sp-t_30)<0.2*norm([3;1;0])
% 
% %T7
% % % execute simulation starting from T0_1 using lqr controller with scenario 1
% [T, p] = simulate_truck(T0_2, @controller_lqr, scen1);
% 
% %T9
% [T, p] = simulate_truck(T0_1, @controller_mpc_1, scen1);
% 
% %T11
% [T, p] = simulate_truck(T0_1, @controller_mpc_2, scen1);

%T15
% simulate_truck(T0_1, @controller_mpc_3, scen1)
% simulate_truck(T0_2, @controller_mpc_3, scen1)

