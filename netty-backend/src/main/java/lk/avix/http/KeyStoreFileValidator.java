package lk.avix.http;

import com.beust.jcommander.IValueValidator;
import com.beust.jcommander.ParameterException;

import java.io.File;

/**
 * Check whether the key store file exists in provided location.
 */
public class KeyStoreFileValidator implements IValueValidator<File> {

    @Override
    public void validate(String name, File file) throws ParameterException {
        if (!file.exists()) {
            throw new ParameterException("Parameter " + name + " should be a valid key store file");
        }
    }
}
