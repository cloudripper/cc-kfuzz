int f(void __user *u, struct x *p, int n) {
  char *b = kmalloc(n * 8, GFP_KERNEL);
  copy_from_user(b, u, n);
  get_user(n, (int __user *)u);
  kfree(p);
  return p->len;
}
