LUA_CFLAGS != pkg-config lua5.1 --cflags
LIBTOOL = libtool --tag=CC --silent

preempter.so: preempter.c
	$(LIBTOOL) --mode=compile cc $(LUA_CFLAGS) -c preempter.c
	$(LIBTOOL) --mode=link cc -rpath /  $(LUA_CFLAGS) -o libpreempter.la preempter.lo
	mv .libs/libpreempter.so.0.0.0 preempter.so
	rm libpreempter.la preempter.lo preempter.o

clean:
	rm libpreempter.la preempter.lo preempter.o preempter.so
	rm -rf .libs

main: preempter.so
