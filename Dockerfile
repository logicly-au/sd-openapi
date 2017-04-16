FROM docker.sdlocal.net/devel/stratperldancer
RUN cpanm -q Devel::Cover Function::Parameters
