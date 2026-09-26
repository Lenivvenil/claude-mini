def complex_function(a, b, c, d, e, f):  # noqa: PLR0913
    if a:
        if b:
            if c:
                if d:
                    if e:
                        if f:
                            return 1
                        return 2
                    elif d:
                        return 3
                    else:
                        return 4
                elif c:
                    if e:
                        return 5
                    else:
                        return 6
            else:
                if d:
                    if e:
                        return 7
                    return 8
                return 9
        elif b:
            if c:
                return 10
            return 11
    return 0
