# File to build minimal R with Seurat version 3.2.3
FROM rocker/r-ver:3.6.3
RUN apt-get update -y && apt-get install -y libcurl4-gnutls-dev libssl-dev libssh2-1-dev libxml2-dev libhdf5-dev libgmp-dev libpng-dev libgsl-dev libxt-dev libcairo2-dev libtiff-dev fftw-dev
RUN R -e "options(repos =  list(CRAN = 'http://mran.revolutionanalytics.com/snapshot/2020-09-15'));  install.packages('Seurat')"