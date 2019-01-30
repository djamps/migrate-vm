FROM centos:centos7
RUN yum -y update && yum -y install perl perl-core perl-App-cpanminus gcc expat-devel && yum clean all
RUN cpanm -n -q pp

WORKDIR /root

ADD cpanfile .
RUN cpanm -n -q --installdeps .
ADD . .
RUN ./build.sh