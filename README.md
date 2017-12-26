# F_CKμ
A slightly optimizing brainf*ck interpreter in approx. 500 lines of x86-64 assembly (AT&amp;T/GAS). Tested on Arch and Debian 9. Obviously not portable.

## Compiling
```sh
$ gcc bf.s -o bf -no-pie 
```
## Running
```sh
$ ./bf path_to_bf_program
```
> Note: No errors will be printed. The interpreter will simply exit with code ``1`` if something goes wrong (e.g., unbalaced brackets). You can check the exit code using ``echo $?``.