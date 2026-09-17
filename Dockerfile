FROM alpine:3.20
RUN echo "hello from github-tests" > /hello.txt
CMD ["cat", "/hello.txt"]
