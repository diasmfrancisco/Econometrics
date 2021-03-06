if !(exist('./ar1.oct','file')) system("mkoctfile ar1.cc"); endif
n = 50; # number of obs
model = "ar1_model"; # the DGP

# true parameters
theta = [0; 0.9];

m_estimation = false;
S = 10000;  # number of simulations
burnin = 100; # initial observations to discard

compute_nodes = 0; # number of nodes to use, not counting master
vc_reps = 100; # number of simulations to use for estimation of covariance and Jacobian of moments

# make Monte Carlo data
modelargs = {"", n, burnin, true};
[data, L, K, snm_draws] = feval(model, theta, modelargs);

# define a few things
M = columns(data) - L - K;

# define bounds for simulated annealing
# bounds for parameters of the model
ub = [1; 1];
lb = [-1; 0];
# bounds for inverse window width
ub = [ub; 3*ones(K,1)];
lb = [lb; 0.1*ones(K,1)];
thetastart = rand(size(ub)).*(ub-lb) + lb;

%  # prepare data, with trimming using kernel density of condvars
%  condvars = data(:,L+1:L+K);
%  d = kernel_density(condvars, condvars);
%  keep = d > quantile(d, 0.02);
%  data = data(keep,:);
endogs = data(:,1:L);
condvars = data(:,L+1:L+K);

# define these for future OLS, for comparison
yy = endogs;
xx = [ones(n,1) condvars];

thetastart = [ols(yy,xx); 1]; # let's be nice to BFGS and use good start values (dangerous)
instruments = data(:,L+K+1:L+K+M);
n = rows(data);

# prewhiten
[endogs, condvars, P] = snm_dataprep(endogs, condvars);

data = [endogs condvars instruments];

# define momentargs for GMM, including random draws for long simulation
modelargs = {"", S, burnin, false};
[junk, junk, junk, snm_draws] = feval(model, theta, modelargs);
modelargs{1} = snm_draws;
momentargs = {model, modelargs, L, K, M, P, true, false};

# samin controls
nt = 3;
ns = 3;
rt = .25;
maxevals = 1e4;
neps = 3;
functol = 1e-6;
paramtol = 1e-3;
verbosity = 2;
minarg = 1;
sacontrol = { lb, ub, nt, ns, rt, maxevals, neps, functol, paramtol, verbosity, 1};

# first round consistent estimator
weight = 1; # weight matrix
[thetahat, obj_value, conv1] = gmm_estimate(thetastart, data, weight, "snm_moments", momentargs, {100,2}, compute_nodes);
#[thetahat, obj_value, conv1] = gmm_estimate(thetastart, data, weight, "snm_moments", momentargs, sacontrol, compute_nodes);

# get covariance matrix of moment conditions
verbose = false; # output from cov matrix routine?
omega = snm_moment_covariance(thetahat, data, momentargs, vc_reps, verbose);

# alternative covariance estimator
V = snm_variance(thetahat, data, weight, "snm_moments", momentargs, vc_reps, compute_nodes, omega);

# print results for SNM
thetahat = thetahat(1:2,:);
se = sqrt(diag(V));
t = thetahat ./ se;
results = [thetahat se t];
rlabels = char("const", "slope");
clabels = char("param", "st. err", "t");
printf("\n\nCheck that the objective function at the final iteration is very\n");
printf("close to zero, otherwise the SNM results are not valid. This script\n");
printf("uses BFGS rather than SA, for speed. If you don't like this, edit the\n");
printf("script to uncomment the line for SA minimization\n");
printf("\nSNM estimation results\n");
prettyprint(results, rlabels, clabels);

# OLS for comparison
mc_ols(yy, xx);