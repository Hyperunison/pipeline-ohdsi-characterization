# Docker image for the OHDSI Characterization Nextflow process.
# Build from the repo root:
#   docker build --network=host -t characterization:latest \
#     -f vendor/pipelines/characterization/v0.1/Dockerfile .
#
# This image extends entsupml/unison-runner-dqd-omop-5.4 which already contains:
#   DatabaseConnector, SqlRender, ResultModelManager, remotes, checkmate,
#   dplyr, readr, rlang, digest, zip, DBI, RSQLite, rJava, CohortGenerator …
#
# We add only the packages still missing for OHDSI/Characterization.

FROM entsupml/unison-runner-dqd-omop-5.4:latest

ENV LD_LIBRARY_PATH=/usr/lib/jvm/java-21-openjdk-amd64/lib/server

RUN Rscript -e 'remotes::install_github("OHDSI/ParallelLogger",   upgrade="never"); if(!requireNamespace("ParallelLogger",   quietly=TRUE)) stop("ParallelLogger install failed")'
RUN Rscript -e 'install.packages("duckdb", repos="http://cran.r-project.org"); if(!requireNamespace("duckdb", quietly=TRUE)) stop("duckdb install failed")'
RUN Rscript -e 'remotes::install_github("OHDSI/Andromeda",        upgrade="never"); if(!requireNamespace("Andromeda",        quietly=TRUE)) stop("Andromeda install failed")'
RUN Rscript -e 'remotes::install_github("OHDSI/FeatureExtraction", upgrade="never"); if(!requireNamespace("FeatureExtraction", quietly=TRUE)) stop("FeatureExtraction install failed")'
RUN Rscript -e 'remotes::install_github("OHDSI/Characterization",  upgrade="never"); if(!requireNamespace("Characterization",  quietly=TRUE)) stop("Characterization install failed")'

# Download PostgreSQL JDBC driver and set the path globally
RUN mkdir -p /jdbc && \
    Rscript -e 'DatabaseConnector::downloadJdbcDrivers("postgresql", pathToDriver="/jdbc")' && \
    echo 'DATABASECONNECTOR_JAR_FOLDER=/jdbc' >> /usr/lib/R/etc/Renviron

# Smoke-test
RUN Rscript -e 'library(Characterization); message("Characterization OK")'

# Reset entrypoint inherited from base image (it runs server.py which is unrelated)
ENTRYPOINT []
CMD ["/bin/bash"]

WORKDIR /app
